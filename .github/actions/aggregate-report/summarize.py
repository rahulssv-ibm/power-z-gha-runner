#!/usr/bin/env python3
"""Merge all verdict-*.tsv into one grouped matrix report and gate on FAIL.

Rows are grouped by (domain, id, profile, arch, os) so a load run with many
instances stays readable: each group shows its status counts and p50/p95
script duration. Exits 1 on any FAIL, or when no results arrived at all.
"""
import csv
import glob
import os
import re
import sys
from collections import Counter, defaultdict

DUR = re.compile(r"dur=(\d+)s")
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
                    rows.append(dict(id=tid, domain=dom, profile=prof, arch=arch, os=osv,
                                     status=status, reason=reason,
                                     dur=int(m.group(1)) if m else None))
    return rows


def pct(values, q):
    values = sorted(values)
    if not values:
        return 0.0
    pos = (len(values) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (pos - lo)


def report(rows):
    groups = defaultdict(list)
    for r in rows:
        groups[(r["domain"], r["id"], r["profile"], r["arch"], r["os"])].append(r)
    total = Counter(r["status"] for r in rows)
    lines = ["# Test suite results", "",
             f"- Checks: **{len(rows)}** across **{len(groups)}** test/runner combinations",
             f"- FAIL: **{total['FAIL']}**  WARN: **{total['WARN']}**  "
             f"PASS: **{total['PASS']}**  XFAIL: **{total['XFAIL']}**  "
             f"INFO: **{total['INFO']}**  SKIP: **{total['SKIP']}**",
             "",
             "| domain | id | profile | arch | os | result | runs | p50 | p95 |",
             "|---|---|---|---|---|---|---:|---:|---:|"]

    def has_fail(rs):
        return any(x["status"] == "FAIL" for x in rs)

    for key, rs in sorted(groups.items(), key=lambda kv: (not has_fail(kv[1]), kv[0])):
        c = Counter(x["status"] for x in rs)
        result = ", ".join(f"{s}×{n}" for s, n in sorted(c.items())) if len(rs) > 1 else rs[0]["status"]
        durs = [x["dur"] for x in rs if x["dur"] is not None]
        p50 = f"{pct(durs, 0.5):.0f}s" if durs else "-"
        p95 = f"{pct(durs, 0.95):.0f}s" if durs else "-"
        lines.append(f"| {' | '.join(key)} | {result} | {len(rs)} | {p50} | {p95} |")
    return "\n".join(lines) + "\n", total["FAIL"]


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
    def mk(tid, status, dur):
        return dict(id=tid, domain="security", profile="container", arch="x", os="y",
                    status=status, reason=f"exit=0 dur={dur}s", dur=dur)
    rows = [mk("a", "FAIL", 3), mk("a", "PASS", 5), mk("b", "PASS", 2)]
    md, nfail = report(rows)
    assert nfail == 1, md
    assert "FAIL×1, PASS×1" in md, md          # grouped instances
    assert "| security | a | container | x | y | FAIL×1, PASS×1 | 2 |" in md, md
    assert md.index("| a |") < md.index("| b |"), md   # failing group sorts first
    assert exit_code(rows, nfail) == 1
    assert exit_code([], 0) == 1                 # nothing ran -> gate fails
    assert exit_code(rows[1:], 0) == 0
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
    rows = load(glob.glob("raw/**/verdict-*.tsv", recursive=True))
    if rows:
        md, nfail = report(rows)
    else:
        md, nfail = "# Test suite results\n\n**No results found** — no suite job produced verdicts.\n", 0
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
    return exit_code(rows, nfail)


if __name__ == "__main__":
    sys.exit(main())
