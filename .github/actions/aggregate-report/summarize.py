#!/usr/bin/env python3
"""Merge all verdict-*.tsv into one grouped matrix report and gate on FAIL.

Rows are grouped by (domain, id, profile, arch, os) so a load run with many
instances stays readable: each group shows its status counts and p50/p95
script duration. Exits 1 on any FAIL, or when no results arrived at all.

GitHub-hosted runners (profile "hosted") are the reference, never gated: our
FAIL becomes PARITY when every check it failed also failed on every hosted
runner that ran the test, i.e. we expose nothing GitHub-hosted does not.
"""
import csv
import glob
import os
import re
import sys
from collections import Counter, defaultdict

DUR = re.compile(r"dur=(\d+)s")
FAILS = re.compile(r"fails=(\S+)")
SANDBOX = re.compile(r"virt=(\S+) backend=(\S+)")


def load(paths):
    rows = []
    for p in paths:
        with open(p) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 8 and parts[0] == "RESULT":
                    _, tid, dom, prof, arch, osv, status, reason = parts
                    m = DUR.search(reason)
                    f = FAILS.search(reason)
                    rows.append(dict(id=tid, domain=dom, profile=prof, arch=arch, os=osv,
                                     status=status, reason=reason,
                                     dur=int(m.group(1)) if m else None,
                                     fails=set(f.group(1).split(",")) if f else set()))
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
    if all(x["status"] == "PARITY" for x in bad):
        return "fails there too"
    if any(x["ref"] is None for x in bad if x["status"] == "FAIL"):
        return "not run on GitHub-hosted"
    only = set().union(*(x["fails"] - x["ref"] for x in bad if x["status"] == "FAIL"))
    return "only here: " + ", ".join(sorted(only)) if only else "failed without naming a check"


def pct(values, q):
    values = sorted(values)
    if not values:
        return 0.0
    pos = (len(values) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (pos - lo)


def report(rows):
    """Our runners' matrix (gating) plus the GitHub-hosted reference (never gates)."""
    ours = [r for r in rows if r["profile"] != "hosted"]
    ref = [r for r in rows if r["profile"] == "hosted"]
    groups = defaultdict(list)
    for r in ours:
        groups[(r["domain"], r["id"], r["profile"], r["arch"], r["os"])].append(r)
    total = Counter(r["status"] for r in ours)
    lines = ["# Test suite results", "",
             f"- Checks: **{len(ours)}** across **{len(groups)}** test/runner combinations"
             + (f", plus **{len(ref)}** on the GitHub-hosted reference" if ref else ""),
             f"- FAIL: **{total['FAIL']}**  PARITY: **{total['PARITY']}**  WARN: **{total['WARN']}**  "
             f"PASS: **{total['PASS']}**  XFAIL: **{total['XFAIL']}**  "
             f"INFO: **{total['INFO']}**  SKIP: **{total['SKIP']}**",
             "- PARITY: fails exactly as on GitHub-hosted runners, so it does not gate",
             "",
             "| domain | id | profile | arch | os | result | runs | p50 | p95 | failing checks | vs GitHub-hosted |",
             "|---|---|---|---|---|---|---:|---:|---:|---|---|"]
    errors = defaultdict(list)   # (domain, id, detail) -> labels
    for key, rs in sorted(groups.items(),
                          key=lambda kv: (not any(x["status"] == "FAIL" for x in kv[1]), kv[0])):
        c = Counter(x["status"] for x in rs)
        result = ", ".join(f"{s}×{n}" for s, n in sorted(c.items())) if len(rs) > 1 else rs[0]["status"]
        durs = [x["dur"] for x in rs if x["dur"] is not None]
        p50 = f"{pct(durs, 0.5):.0f}s" if durs else "-"
        p95 = f"{pct(durs, 0.95):.0f}s" if durs else "-"
        bad = [x for x in rs if x["status"] in ("FAIL", "PARITY")]
        checks = ", ".join(sorted(set().union(*(x["fails"] for x in bad))))
        vs = versus(bad) if bad else ""
        lines.append(f"| {' | '.join(key)} | {result} | {len(rs)} | {p50} | {p95} | {checks} | {vs} |")
        if c["FAIL"]:
            errors[(key[0], key[1], f"{checks or 'see the job logs'} ({vs})")].append(" ".join(key[2:]))
    if ref:
        lines += ["", "## GitHub-hosted reference", "",
                  "Never gates. Rows not listed passed, or are INFO/SKIP.", "",
                  "| domain | id | arch | os | result | failing checks |",
                  "|---|---|---|---|---|---|"]
        for r in sorted(ref, key=lambda r: (r["domain"], r["id"], r["arch"], r["os"])):
            if r["status"] not in ("PASS", "INFO", "SKIP"):
                lines.append(f"| {r['domain']} | {r['id']} | {r['arch']} | {r['os']} | "
                             f"{r['status']} | {', '.join(sorted(r['fails']))} |")
    # One annotation per test, not per runner: GitHub shows only 10 per step.
    notes = [f"::error title=FAIL {d}/{i}::{detail} on {', '.join(where)}"
             for (d, i, detail), where in sorted(errors.items())]
    return "\n".join(lines) + "\n", total["FAIL"], notes


def sandboxes(paths):
    """Which sandbox (virt type, LXD or Incus) served each probe job."""
    seen = Counter()
    for p in paths:
        with open(p) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 8 and parts[0] == "RESULT" and parts[1] == "host-info":
                    m = SANDBOX.search(parts[7])
                    if m:
                        seen[(parts[3], parts[4], parts[5], m.group(1), m.group(2))] += 1
    if not seen:
        return ""
    lines = ["", "## Sandboxes that ran the probe", "",
             "| profile | arch | os | virt | backend | jobs |",
             "|---|---|---|---|---|---:|"]
    for key, n in sorted(seen.items()):
        lines.append(f"| {' | '.join(key)} | {n} |")
    return "\n".join(lines) + "\n"


def exit_code(rows, nfail):
    # No rows means no suite reported anything: never a pass.
    return 1 if (not rows or nfail) else 0


def selftest():
    def mk(tid, status, dur, profile="container", fails=()):
        return dict(id=tid, domain="security", profile=profile, arch="x", os="y",
                    status=status, reason=f"exit=0 dur={dur}s", dur=dur, fails=set(fails))
    rows = [mk("a", "FAIL", 3), mk("a", "PASS", 5), mk("b", "PASS", 2)]
    for r in rows:
        r["ref"] = None
    md, nfail, errors = report(rows)
    assert nfail == 1, md
    assert "FAIL×1, PASS×1" in md, md          # grouped instances
    assert "| security | a | container | x | y | FAIL×1, PASS×1 | 2 |" in md, md
    assert md.index("| a |") < md.index("| b |"), md   # failing group sorts first
    assert exit_code(rows, nfail) == 1
    assert exit_code([], 0) == 1                 # nothing ran -> gate fails
    assert exit_code(rows[1:], 0) == 0
    # parity: hosted fails the same checks -> PARITY; we fail more -> FAIL;
    # one hosted runner blocks it -> FAIL; hosted rows never gate
    ref = [mk("p", "FAIL", 1, "hosted", {"a", "b"}), mk("p", "FAIL", 1, "hosted", {"a"}),
           mk("q", "FAIL", 1, "hosted", {"a"}), mk("q", "PASS", 1, "hosted"),
           mk("r", "SKIP", 1, "hosted")]
    ours = [mk("p", "FAIL", 1, fails={"a"}), mk("p", "FAIL", 1, fails={"a", "b"}),
            mk("q", "FAIL", 1, fails={"a"}), mk("r", "FAIL", 1, fails={"a"}),
            mk("p", "FAIL", 1)]
    parity(ref + ours)
    assert [r["status"] for r in ours] == ["PARITY", "FAIL", "FAIL", "FAIL", "FAIL"], ours
    md, nfail, errors = report(ref + ours)
    assert nfail == 4 and "PARITY: **1**" in md, md
    head, hosted = md.split("## GitHub-hosted reference")
    assert "| hosted |" not in head and "| security | p | x | y | FAIL | a, b |" in hosted, md
    assert "only here: b" in head, md          # p failed b, which one hosted runner blocks
    assert "| r | container | x | y | FAIL | 1 | 1s | 1s | a | not run on GitHub-hosted |" in head, md  # hosted SKIPped r
    assert len(errors) == 3 and all(e.startswith("::error title=FAIL security/") for e in errors), errors
    md, _, errors = report([mk("s", "FAIL", 1, fails={"a"}) | {"ref": None, "arch": a} for a in "xyz"])
    assert errors == ["::error title=FAIL security/s::a (not run on GitHub-hosted) on container x y, "
                      "container y y, container z y"], errors   # one annotation, all runners
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False) as f:
        f.write("RESULT\thost-info\tprobe\tvm\tppc64le\t24.04\tPASS\tvirt=kvm backend=incus\n"
                "RESULT\thost-info\tprobe\tcontainer\ts390x\t22.04\tPASS\tvirt=lxc backend=lxd\n"
                "RESULT\tenv\tprobe\tvm\tppc64le\t24.04\tPASS\tcollected\n")
    sb = sandboxes([f.name])
    os.unlink(f.name)
    assert "| vm | ppc64le | 24.04 | kvm | incus | 1 |" in sb, sb
    assert "| container | s390x | 22.04 | lxc | lxd | 1 |" in sb, sb
    assert sandboxes([]) == ""
    print("summarize selftest: OK")
    return 0


def main():
    if "--selftest" in sys.argv:
        return selftest()
    rows = parity(load(glob.glob("raw/**/verdict-*.tsv", recursive=True)))
    if rows:
        md, nfail, errors = report(rows)
    else:
        md, nfail, errors = "# Test suite results\n\n**No results found** — no suite job produced verdicts.\n", 0, []
    md += sandboxes(glob.glob("raw/**/detail-probe.tsv", recursive=True))
    with open("summary.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["domain", "id", "profile", "arch", "os", "status", "dur_s", "reason"])
        for r in rows:
            w.writerow([r["domain"], r["id"], r["profile"], r["arch"], r["os"],
                        r["status"], "" if r["dur"] is None else r["dur"], r["reason"]])
    sp = os.environ.get("GITHUB_STEP_SUMMARY")
    if sp:
        with open(sp, "a") as f:
            f.write(md)
    print(md)
    print("\n".join(errors))   # one annotation per failing row on the run page
    return exit_code(rows, nfail)


if __name__ == "__main__":
    sys.exit(main())
