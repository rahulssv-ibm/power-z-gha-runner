#!/usr/bin/env python3
"""Merge all verdict-*.tsv into one matrix report and gate on FAIL."""
import csv
import glob
import os
import sys


def load(paths):
    rows = []
    for p in paths:
        with open(p) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 8 and parts[0] == "RESULT":
                    _, tid, dom, prof, arch, osv, status, reason = parts
                    rows.append(dict(id=tid, domain=dom, profile=prof,
                                     arch=arch, os=osv, status=status, reason=reason))
    return rows


def report(rows):
    fails = [r for r in rows if r["status"] == "FAIL"]
    warns = [r for r in rows if r["status"] == "WARN"]
    lines = ["# Test suite results", "",
             f"- Total checks: **{len(rows)}**",
             f"- FAIL: **{len(fails)}**  WARN: **{len(warns)}**",
             f"- PASS: **{sum(r['status'] == 'PASS' for r in rows)}**  "
             f"XFAIL: **{sum(r['status'] == 'XFAIL' for r in rows)}**  "
             f"SKIP: **{sum(r['status'] == 'SKIP' for r in rows)}**",
             "",
             "| domain | id | profile | arch | os | status |",
             "|---|---|---|---|---|---|"]
    for r in sorted(rows, key=lambda r: (r["status"] != "FAIL", r["domain"], r["id"])):
        lines.append(f"| {r['domain']} | {r['id']} | {r['profile']} | "
                     f"{r['arch']} | {r['os']} | {r['status']} |")
    return "\n".join(lines) + "\n", len(fails)


def main():
    if "--selftest" in sys.argv:
        rows = [dict(id="a", domain="security", profile="container", arch="x", os="y", status="FAIL", reason=""),
                dict(id="b", domain="capability", profile="vm", arch="x", os="y", status="PASS", reason="")]
        md, nfail = report(rows)
        assert nfail == 1 and "FAIL: **1**" in md, md
        print("summarize selftest: OK")
        return 0
    rows = load(glob.glob("raw/**/verdict-*.tsv", recursive=True))
    md, nfail = report(rows)
    with open("summary.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["domain", "id", "profile", "arch", "os", "status", "reason"])
        for r in rows:
            w.writerow([r["domain"], r["id"], r["profile"], r["arch"], r["os"], r["status"], r["reason"]])
    sp = os.environ.get("GITHUB_STEP_SUMMARY")
    if sp:
        with open(sp, "a") as f:
            f.write(md)
    print(md)
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
