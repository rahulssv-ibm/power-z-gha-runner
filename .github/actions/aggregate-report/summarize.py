#!/usr/bin/env python3
"""Merge all verdict-*.tsv into one grouped matrix report and gate on FAIL.

Rows are grouped by (domain, id, profile, label) so a load run with many
instances stays readable: each group shows its status counts and p50/p95
script duration. Exits 1 on any FAIL, or when no results arrived at all.

GitHub-hosted runners (profile "hosted") are the reference, never gated: our
FAIL becomes PARITY when every check it failed also failed on every hosted
runner that ran the test, i.e. we expose nothing GitHub-hosted does not.
A FAIL becomes KNOWN (not gating either) when each check it failed is parity
or an accepted known finding in tests/known-findings.tsv; any other check
keeps it FAIL, so a new leak in an accepted test still gates.

Every FAIL is then explained: where it failed, the reason each failed check
gave (detail-*.tsv next to the verdict), how to fix it (the fix column of
tests/<domain>/manifest.tsv) and where its log is. The runs-on label is read
from the artifact name, result-<domain>-<profile>-<label>-<instance>.
"""
import csv
import glob
import os
import re
import sys
from collections import Counter, defaultdict

DUR = re.compile(r"dur=(\d+)s")
EXIT = re.compile(r"exit=(\d+)")
FAILS = re.compile(r"fails=(\S+)")
SANDBOX = re.compile(r"virt=(\S+) backend=(\S+)")
ARTIFACT = re.compile(r"result-[^-]+-(?:container|vm|hosted)-(.+)-(\d+)$")
DOMAINS = ["security", "capability", "stress", "probe"]   # explained in this order


def where(path):
    """(label, instance) from the artifact directory a result file sits in."""
    m = ARTIFACT.match(os.path.basename(os.path.dirname(path)))
    return (m.group(1), m.group(2)) if m else (None, "1")


def reasons(verdict_path):
    """Check id -> reason, for each FAIL in the detail file next to a verdict."""
    d = os.path.join(os.path.dirname(verdict_path),
                     os.path.basename(verdict_path).replace("verdict-", "detail-", 1))
    out = {}
    if os.path.exists(d):
        with open(d) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 8 and parts[0] == "RESULT" and parts[6] == "FAIL":
                    out.setdefault(parts[1], parts[7])
    return out


def load(paths):
    rows = []
    for p in paths:
        label, instance = where(p)
        why = reasons(p)
        with open(p) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 8 and parts[0] == "RESULT":
                    _, tid, dom, prof, arch, osv, status, reason = parts
                    m = DUR.search(reason)
                    f = FAILS.search(reason)
                    fails = set(f.group(1).split(",")) if f else set()
                    rows.append(dict(id=tid, domain=dom, profile=prof, arch=arch, os=osv,
                                     label=label or f"{arch} {osv}", instance=instance,
                                     status=status, reason=reason,
                                     dur=int(m.group(1)) if m else None,
                                     fails=fails, why={c: why.get(c, "") for c in fails}))
    return rows


def hints(root="."):
    """(domain, id) -> how to fix it, from the manifests' fix column."""
    out = {}
    for p in glob.glob(os.path.join(root, "tests", "*", "manifest.tsv")):
        domain = os.path.basename(os.path.dirname(p))
        with open(p) as f:
            for line in f:
                cols = line.rstrip("\n").split("\t")
                if len(cols) >= 7 and not cols[0].startswith("#") and cols[6] not in ("", "-"):
                    out[(domain, cols[0])] = cols[6]
    return out


def known(root="."):
    """(domain, id) -> {check: why it is accepted}, from tests/known-findings.tsv."""
    out = defaultdict(dict)
    p = os.path.join(root, "tests", "known-findings.tsv")
    if os.path.exists(p):
        with open(p) as f:
            for line in f:
                cols = line.rstrip("\n").split("\t")
                if len(cols) >= 4 and not cols[0].startswith("#"):
                    out[(cols[0], cols[1])][cols[2]] = cols[3]
    return out


def accept(rows, accepted):
    """Downgrade our FAIL to KNOWN when every failed check is parity or an accepted known finding."""
    for r in rows:
        ok = set(accepted.get((r["domain"], r["id"]), ()))
        r["accepted"] = r["fails"] & ok   # versus() leaves these out of "only here"
        if (r["profile"] != "hosted" and r["status"] == "FAIL" and r["fails"] & ok
                and r["fails"] <= ok | (r["ref"] or set())):
            r["status"] = "KNOWN"
    return rows


def parity(rows):
    """Downgrade our FAIL to PARITY when GitHub-hosted fails the same checks."""
    ref = defaultdict(list)
    for r in rows:
        if r["profile"] == "hosted" and r["status"] != "SKIP":
            ref[(r["domain"], r["id"])].append(r["fails"])
    for r in rows:
        sets = ref.get((r["domain"], r["id"]))
        # Checks every hosted runner failed; None = no hosted run to compare with.
        r["ref"] = set.intersection(*sets) if sets else None
        # Empty fails = the script crashed or failed without naming a check: never parity.
        if (r["profile"] != "hosted" and r["status"] == "FAIL" and r["fails"]
                and r["ref"] is not None and r["fails"] <= r["ref"]):
            r["status"] = "PARITY"
    return rows


def versus(bad):
    """How our failing rows compare with GitHub-hosted."""
    if not any(x["status"] == "FAIL" for x in bad):
        return "known finding" if any(x["status"] == "KNOWN" for x in bad) else "fails there too"
    if any(x["ref"] is None for x in bad if x["status"] == "FAIL"):
        return "not run on GitHub-hosted"
    only = set().union(*(x["fails"] - x["ref"] - x.get("accepted", set()) for x in bad if x["status"] == "FAIL"))
    return "only here: " + ", ".join(sorted(only)) if only else "failed without naming a check"


def pct(values, q):
    values = sorted(values)
    if not values:
        return 0.0
    pos = (len(values) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (pos - lo)


def order(key):
    """Sort (domain, id, ...) keys security first, then by name."""
    d = key[0]
    return (DOMAINS.index(d) if d in DOMAINS else len(DOMAINS), key)


def checks_of(rs):
    """Failed check -> first reason given, across rows; a FAIL naming no check reads its exit code."""
    out = {}
    for x in rs:
        for c in sorted(x["fails"]):
            if not out.get(c):
                out[c] = x["why"].get(c, "")
        if not x["fails"]:
            e = EXIT.search(x["reason"])
            out.setdefault("(none named)", f"the script exited {e.group(1) if e else '?'} "
                                           "without reporting a check: read its log")
    return out


def runs_on(rs):
    """'profile label (n of m runs)' per label a test failed on."""
    c = defaultdict(lambda: [0, 0])
    for x in rs:
        c[(x["profile"], x["label"])][0] += 1
    return ", ".join(f"{p} {lb}" + (f" ({n} runs)" if n > 1 else "") for (p, lb), (n, _) in sorted(c.items()))


def esc(s):
    """Escape a workflow-command message (newlines become %0A)."""
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def explain(fails, warns, parities, fixes, knowns=(), accepted=None):
    """Markdown: what failed, why, and how to fix it; plus the annotations for the run page."""
    lines, notes = [], []
    if fails:
        lines += ["", "## What failed and how to fix it", ""]
    for (d, i), rs in sorted(fails.items(), key=lambda kv: order(kv[0])):
        checks = checks_of(rs)
        fix = fixes.get((d, i), f"no fix recorded: read the header of tests/{d}/ and its manifest row.")
        x = rs[0]
        lines += [f"### FAIL `{d}/{i}`", "",
                  f"- **On:** {runs_on(rs)}",
                  f"- **vs GitHub-hosted:** {versus(rs)}",
                  "- **Failed checks:**"]
        lines += [f"  - `{c}`: {why or 'no reason recorded'}" for c, why in checks.items()]
        lines += [f"- **How to fix:** {fix}",
                  f"- **Log:** job `{d} {x['label']} #{x['instance']}`, step `Run {d}`: the folded "
                  f"`{d}/{i}` group and the block after it; or `logs/{i}.log` in artifact "
                  f"`result-{d}-{x['profile']}-{x['label']}-{x['instance']}`.", ""]
        # Lead with what gates (vs GitHub-hosted): the first line is all a collapsed annotation shows.
        vs = versus(rs)
        msg = ([vs[:1].upper() + vs[1:]] + [f"{c}: {r}" if r else c for c, r in checks.items()]
               + [f"Fix: {fix}", f"On: {runs_on(rs)}"])
        notes.append(f"::error title=FAIL {d}/{i}::{esc(chr(10).join(msg))}")
    if warns:
        lines += ["", "## Needs an explanation (WARN)", "",
                  "Succeeded where the manifest expects a failure (`XFAIL`): the runner now allows "
                  "something it did not. Explain it before promoting; if intended, set the test's "
                  "expected result to `PASS` in `tests/<domain>/manifest.tsv`.", ""]
        lines += [f"- `{d}/{i}` on {runs_on(rs)}" for (d, i), rs in sorted(warns.items(), key=lambda kv: order(kv[0]))]
    if knowns:
        lines += ["", "## Known findings (KNOWN, accepted, do not gate)", "",
                  "Listed in `tests/known-findings.tsv`. A check not listed there, and not failing on "
                  "GitHub-hosted too, turns the test back into a FAIL.", ""]
        for (d, i), rs in sorted(knowns.items(), key=lambda kv: order(kv[0])):
            why = accepted.get((d, i), {})
            lines.append(f"- `{d}/{i}` on {runs_on(rs)}:")
            lines += [f"  - `{c}`: " + (f"accepted: {why[c]}" if c in why else "same as GitHub-hosted")
                      for c in checks_of(rs)]
    if parities:
        lines += ["", "## Same as GitHub-hosted (PARITY, does not gate)", ""]
        for (d, i), rs in sorted(parities.items(), key=lambda kv: order(kv[0])):
            lines.append(f"- `{d}/{i}` ({', '.join(checks_of(rs))}) on {runs_on(rs)}. "
                         f"To close it anyway: {fixes.get((d, i), 'see its manifest row')}")
    return lines, notes


def report(rows, fixes=None, selected=(), accepted=None):
    """Our runners' matrix (gating), why each FAIL failed, plus the GitHub-hosted reference."""
    fixes, accepted = fixes or {}, accepted or {}
    ours = [r for r in rows if r["profile"] != "hosted"]
    ref = [r for r in rows if r["profile"] == "hosted"]
    groups = defaultdict(list)
    for r in ours:
        groups[(r["domain"], r["id"], r["profile"], r["label"])].append(r)
    total = Counter(r["status"] for r in ours)
    lines = ["# Test suite results", "",
             f"- Checks: **{len(ours)}** across **{len(groups)}** test/runner combinations"
             + (f", plus **{len(ref)}** on the GitHub-hosted reference" if ref else ""),
             f"- FAIL: **{total['FAIL']}**  PARITY: **{total['PARITY']}**  KNOWN: **{total['KNOWN']}**  "
             f"WARN: **{total['WARN']}**  "
             f"PASS: **{total['PASS']}**  XFAIL: **{total['XFAIL']}**  "
             f"INFO: **{total['INFO']}**  SKIP: **{total['SKIP']}**",
             "- PARITY: fails exactly as on GitHub-hosted runners, so it does not gate",
             "- KNOWN: fails only on checks that are parity or accepted known findings; does not gate",
             "- Each FAIL is explained, with how to fix it, below the table",
             "",
             "| domain | id | profile | label | result | runs | p50 | p95 | failing checks | vs GitHub-hosted |",
             "|---|---|---|---|---|---:|---:|---:|---|---|"]
    fails, warns, parities, knowns = defaultdict(list), defaultdict(list), defaultdict(list), defaultdict(list)
    for key, rs in sorted(groups.items(),
                          key=lambda kv: (not any(x["status"] == "FAIL" for x in kv[1]), order(kv[0]))):
        c = Counter(x["status"] for x in rs)
        result = ", ".join(f"{s}×{n}" for s, n in sorted(c.items())) if len(rs) > 1 else rs[0]["status"]
        durs = [x["dur"] for x in rs if x["dur"] is not None]
        p50 = f"{pct(durs, 0.5):.0f}s" if durs else "-"
        p95 = f"{pct(durs, 0.95):.0f}s" if durs else "-"
        bad = [x for x in rs if x["status"] in ("FAIL", "PARITY", "KNOWN")]
        checks = ", ".join(sorted(set().union(*(x["fails"] for x in bad))))
        vs = versus(bad) if bad else ""
        lines.append(f"| {' | '.join(key)} | {result} | {len(rs)} | {p50} | {p95} | {checks} | {vs} |")
        for x in rs:
            {"FAIL": fails, "WARN": warns, "PARITY": parities,
             "KNOWN": knowns}.get(x["status"], {}).setdefault(key[:2], []).append(x)
    more, notes = explain(fails, warns, parities, fixes, knowns, accepted)
    lines += more
    missing = [lb for lb in selected if lb and lb not in {r["label"] for r in ours}]
    if missing:
        lines += ["", "## Labels with no results", "",
                  "Their jobs crashed, were cancelled, or never got a runner. A label no runner "
                  "serves stays queued until GitHub cancels it: untick it for this environment.", ""]
        lines += [f"- `{lb}`" for lb in missing]
        notes += [f"::warning title=No results from {lb}::No suite reported from this label. "
                  "Check its jobs; untick it if this environment does not serve it." for lb in missing]
    if ref:
        lines += ["", "## GitHub-hosted reference", "",
                  "Never gates. Rows not listed passed, or are INFO/SKIP.", "",
                  "| domain | id | label | result | failing checks |",
                  "|---|---|---|---|---|"]
        for r in sorted(ref, key=lambda r: (r["domain"], r["id"], r["label"])):
            if r["status"] not in ("PASS", "INFO", "SKIP"):
                lines.append(f"| {r['domain']} | {r['id']} | {r['label']} | "
                             f"{r['status']} | {', '.join(sorted(r['fails']))} |")
    return "\n".join(lines) + "\n", total["FAIL"], notes


def sandboxes(paths):
    """Which sandbox (virt type, LXD or Incus) served each probe job."""
    seen = Counter()
    for p in paths:
        label = where(p)[0]
        with open(p) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 8 and parts[0] == "RESULT" and parts[1] == "host-info":
                    m = SANDBOX.search(parts[7])
                    if m:
                        seen[(parts[3], label or f"{parts[4]} {parts[5]}", m.group(1), m.group(2))] += 1
    if not seen:
        return ""
    lines = ["", "## Sandboxes that ran the probe", "",
             "| profile | label | virt | backend | jobs |",
             "|---|---|---|---|---:|"]
    for key, n in sorted(seen.items()):
        lines.append(f"| {' | '.join(key)} | {n} |")
    return "\n".join(lines) + "\n"


def exit_code(rows, nfail):
    # No rows means no suite reported anything: never a pass.
    return 1 if (not rows or nfail) else 0


def selftest():
    import tempfile

    def mk(tid, status, dur, profile="container", fails=(), label="L", why=None):
        return dict(id=tid, domain="security", profile=profile, arch="x", os="y", label=label,
                    instance="1", status=status, reason=f"exit=1 dur={dur}s", dur=dur,
                    fails=set(fails), why=why or {})
    rows = [mk("a", "FAIL", 3), mk("a", "PASS", 5), mk("b", "PASS", 2)]
    for r in rows:
        r["ref"] = None
    md, nfail, errors = report(rows)
    assert nfail == 1, md
    assert "FAIL×1, PASS×1" in md, md          # grouped instances
    assert "| security | a | container | L | FAIL×1, PASS×1 | 2 |" in md, md
    assert md.index("| a |") < md.index("| b |"), md   # failing group sorts first
    assert "the script exited 1 without reporting a check" in md, md   # a FAIL naming no check
    assert exit_code(rows, nfail) == 1
    assert exit_code([], 0) == 1                 # nothing ran -> gate fails
    assert exit_code(rows[1:], 0) == 0
    # parity: hosted fails the same checks -> PARITY; we fail more -> FAIL;
    # one hosted runner blocks it -> FAIL; hosted rows never gate
    ref = [mk("p", "FAIL", 1, "hosted", {"a", "b"}, "ubuntu-24.04"), mk("p", "FAIL", 1, "hosted", {"a"}, "ubuntu-24.04-arm"),
           mk("q", "FAIL", 1, "hosted", {"a"}), mk("q", "PASS", 1, "hosted"),
           mk("r", "SKIP", 1, "hosted")]
    ours = [mk("p", "FAIL", 1, fails={"a"}), mk("p", "FAIL", 1, fails={"a", "b"}),
            mk("q", "FAIL", 1, fails={"a"}), mk("r", "FAIL", 1, fails={"a"}),
            mk("p", "FAIL", 1)]
    parity(ref + ours)
    assert [r["status"] for r in ours] == ["PARITY", "FAIL", "FAIL", "FAIL", "FAIL"], ours
    md, nfail, errors = report(ref + ours, {("security", "p"): "do the p fix"})
    assert nfail == 4 and "PARITY: **1**" in md, md
    head, hosted = md.split("## GitHub-hosted reference")
    assert "| hosted |" not in head and "| security | p | ubuntu-24.04 | FAIL | a, b |" in hosted, md
    assert "only here: b" in head, md          # p failed b, which one hosted runner blocks
    assert "| r | container | L | FAIL | 1 | 1s | 1s | a | not run on GitHub-hosted |" in head, md  # hosted SKIPped r
    assert "- **How to fix:** do the p fix" in head, md
    assert "no fix recorded" in head, md        # q and r have no fix column
    assert "## Same as GitHub-hosted (PARITY, does not gate)" in head, md
    assert len(errors) == 3 and all(e.startswith("::error title=FAIL security/") for e in errors), errors
    # one annotation per test, every runner listed, the reason and the fix on their own lines
    rs = [mk("s", "FAIL", 1, fails={"a"}, label=lb, why={"a": "port open"}) | {"ref": None}
          for lb in ("ubuntu-24.04-ppc64le", "ubuntu-24.04-ppc64le-p10")]
    md, _, errors = report(rs, {("security", "s"): "close the port"}, ["ubuntu-24.04-ppc64le", "ubuntu-24.04-s390x"])
    assert errors[0] == ("::error title=FAIL security/s::Not run on GitHub-hosted%0Aa: port open%0AFix: close the port%0A"
                         "On: container ubuntu-24.04-ppc64le, container ubuntu-24.04-ppc64le-p10"), errors
    assert "  - `a`: port open" in md, md
    # a selected label that reported nothing is named
    assert "## Labels with no results" in md and "- `ubuntu-24.04-s390x`" in md, md
    assert errors[1].startswith("::warning title=No results from ubuntu-24.04-s390x::"), errors
    # KNOWN: every failed check is parity or accepted; an unlisted extra check stays FAIL
    href = [mk("k", "FAIL", 1, "hosted", {"pub"})]
    ours = [mk("k", "FAIL", 1, fails={"pub", "key"}, label="A"), mk("k", "FAIL", 1, fails={"key"}, label="B"),
            mk("k", "FAIL", 1, fails={"pub", "key", "token"}, label="C"), mk("k", "FAIL", 1, label="D")]
    acc = {("security", "k"): {"key": "ephemeral, dies with the job"}}
    accept(parity(href + ours), acc)
    assert [r["status"] for r in ours] == ["KNOWN", "KNOWN", "FAIL", "FAIL"], ours
    md, nfail, errors = report(href + ours, {}, (), acc)
    assert nfail == 2 and "KNOWN: **2**" in md, md
    assert "| security | k | container | A | KNOWN | 1 | 1s | 1s | key, pub | known finding |" in md, md
    assert "  - `key`: accepted: ephemeral, dies with the job" in md and "  - `pub`: same as GitHub-hosted" in md, md
    assert "only here: token" in md, md
    # WARN rows are listed for an explanation, never gated
    md, nfail, _ = report([mk("w", "WARN", 1) | {"ref": None}])
    assert nfail == 0 and "## Needs an explanation (WARN)" in md and "- `security/w` on container L" in md, md
    # files: the label comes from the artifact directory, the reason from the detail file
    with tempfile.TemporaryDirectory() as t:
        d = os.path.join(t, "raw", "result-security-container-ubuntu-24.04-ppc64le-p10-3")
        os.makedirs(d)
        with open(os.path.join(d, "verdict-security.tsv"), "w") as f:
            f.write("RESULT\tegress\tsecurity\tcontainer\tppc64le\t24.04\tFAIL\texit=1 dur=6s fails=port:irc\n")
        with open(os.path.join(d, "detail-security.tsv"), "w") as f:
            f.write("RESULT\tport:irc\tsecurity\tcontainer\tppc64le\t24.04\tFAIL\tirc reachable\n")
        with open(os.path.join(d, "detail-probe.tsv"), "w") as f:
            f.write("RESULT\thost-info\tprobe\tcontainer\tppc64le\t24.04\tPASS\tvirt=lxc backend=lxd\n")
        (r,) = load(glob.glob(os.path.join(t, "raw", "**", "verdict-*.tsv"), recursive=True))
        assert (r["label"], r["instance"], r["why"]) == ("ubuntu-24.04-ppc64le-p10", "3", {"port:irc": "irc reachable"}), r
        sb = sandboxes([os.path.join(d, "detail-probe.tsv")])
        assert "| container | ubuntu-24.04-ppc64le-p10 | lxc | lxd | 1 |" in sb, sb
        os.makedirs(os.path.join(t, "tests", "security"))
        with open(os.path.join(t, "tests", "security", "manifest.tsv"), "w") as f:
            f.write("# id\tscript\tprofiles\texpected_container\texpected_vm\tissue\tfix\n"
                    "egress\te.sh\tcontainer\tPASS\tPASS\t-\tturn the filter on\n"
                    "other\to.sh\tcontainer\tPASS\tPASS\t-\t-\n")
        assert hints(t) == {("security", "egress"): "turn the filter on"}, hints(t)
        with open(os.path.join(t, "tests", "known-findings.tsv"), "w") as f:
            f.write("# domain\tid\tcheck\twhy\nsecurity\tegress\tport:irc\tbecause\n")
        assert known(t) == {("security", "egress"): {"port:irc": "because"}}, known(t)
    assert sandboxes([]) == ""
    print("summarize selftest: OK")
    return 0


def main():
    if "--selftest" in sys.argv:
        return selftest()
    accepted = known()
    rows = accept(parity(load(glob.glob("raw/**/verdict-*.tsv", recursive=True))), accepted)
    selected = [x for x in os.environ.get("SELECTED_LABELS", "").split(",") if x]
    if rows:
        md, nfail, errors = report(rows, hints(), selected, accepted)
    else:
        md, nfail, errors = "# Test suite results\n\n**No results found** — no suite job produced verdicts.\n", 0, []
    md += sandboxes(glob.glob("raw/**/detail-probe.tsv", recursive=True))
    with open("summary.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["domain", "id", "profile", "label", "arch", "os", "status", "dur_s", "reason"])
        for r in rows:
            w.writerow([r["domain"], r["id"], r["profile"], r["label"], r["arch"], r["os"],
                        r["status"], "" if r["dur"] is None else r["dur"], r["reason"]])
    sp = os.environ.get("GITHUB_STEP_SUMMARY")
    if sp:
        with open(sp, "a") as f:
            f.write(md)
    print(md)
    print("\n".join(errors))   # one annotation per failing test on the run page
    return exit_code(rows, nfail)


if __name__ == "__main__":
    sys.exit(main())
