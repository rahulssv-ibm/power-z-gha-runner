#!/usr/bin/env python3
"""Turn run-all's runner-label selection into one job matrix per profile.

Labels come from the ticked checkboxes (each input id is a label with its
'.' written as '_', e.g. ubuntu-24_04-ppc64le-p10) plus the free-text
`labels` input. When neither selects anything, the RUNNER_LABELS repository
variable is used, so each environment can keep its own default.

Profile, arch and OS are read from the label itself,

    ubuntu-<os>-<arch>[-<anything>...][-vm]

so any label that follows the naming runs without editing this file. GitHub
caps one matrix at 256 jobs, so labels x instances per profile must fit.
"""
import json
import os
import re
import sys

ARCHES = {"ppc64le": "ppc64le", "s390x": "s390x",
          "x64": "x86_64", "x86_64": "x86_64", "amd64": "x86_64",
          "arm64": "aarch64", "aarch64": "aarch64"}
# GitHub-hosted reference for the parity gate: every arch, one copy.
HOSTED = [("ubuntu-22.04", "x86_64", "22.04"), ("ubuntu-24.04", "x86_64", "24.04"),
          ("ubuntu-22.04-arm", "aarch64", "22.04"), ("ubuntu-24.04-arm", "aarch64", "24.04")]
MAX_JOBS = 256
LABEL = re.compile(r"ubuntu-(\d\d\.\d\d|latest)-([a-z0-9][a-z0-9.-]*)")


class PlanError(Exception):
    pass


def parse(label):
    m = LABEL.fullmatch(label)
    arch = ARCHES.get(m.group(2).split("-")[0]) if m else None
    if not arch:
        raise PlanError(f"'{label}' does not read as ubuntu-<os>-<arch>[-...][-vm] with arch one of "
                        f"{', '.join(sorted(set(ARCHES)))}. GitHub-hosted labels need not be "
                        "selected: they always run as the reference.")
    profile = "vm" if "vm" in m.group(2).split("-")[1:] else "container"
    return {"label": label, "profile": profile, "arch": arch, "os": m.group(1)}


def select(inputs, fallback=""):
    """Labels to run, and where they came from."""
    ticked = [k.replace("_", ".") for k, v in inputs.items()
              if k.startswith("ubuntu-") and v in (True, "true")]
    typed = [x for x in re.split(r"[\s,]+", str(inputs.get("labels") or "")) if x]
    labels, source = ticked + typed, "the run form"
    if not labels:
        labels = [x for x in re.split(r"[\s,]+", fallback or "") if x]
        source = "the RUNNER_LABELS repository variable"
    if not labels:
        raise PlanError("No runner labels selected. Tick the labels this environment serves on the "
                        "Run workflow form, type them into 'labels', or set the RUNNER_LABELS "
                        "repository variable (comma-separated) as this repository's default.")
    return list(dict.fromkeys(labels)), source


def plan(labels, instances):
    parsed = [parse(x) for x in labels]
    out = {}
    for profile in ("container", "vm"):
        jobs = [dict(p, instance=i) for p in parsed if p["profile"] == profile
                for i in range(1, instances + 1)]
        for j in jobs:
            del j["profile"]
        if len(jobs) > MAX_JOBS:
            raise PlanError(f"{len(jobs)} {profile} jobs exceed GitHub's {MAX_JOBS}-per-matrix limit: "
                            "select fewer labels or lower instances.")
        out[profile] = json.dumps({"include": jobs}) if jobs else ""
    out["hosted"] = json.dumps({"include": [{"label": l, "arch": a, "os": o, "instance": 1}
                                            for l, a, o in HOSTED]})
    out["labels"] = ",".join(labels)
    return out, parsed


def summary(parsed, source, instances):
    lines = ["# Runner labels", "", f"From {source}, {instances} instance(s) each.", "",
             "| label | profile | arch | os |", "|---|---|---|---|"]
    lines += [f"| {p['label']} | {p['profile']} | {p['arch']} | {p['os']} |" for p in parsed]
    lines += ["", "GitHub-hosted " + ", ".join(l for l, _, _ in HOSTED) + " run as the parity "
              "reference. A label no runner serves leaves its jobs queued until GitHub cancels "
              "them; untick it for that environment."]
    return "\n".join(lines) + "\n"


def selftest():
    assert parse("ubuntu-24.04-ppc64le-p10") == {"label": "ubuntu-24.04-ppc64le-p10", "profile": "container",
                                                 "arch": "ppc64le", "os": "24.04"}
    assert parse("ubuntu-22.04-ppc64le-vm")["profile"] == "vm"
    assert parse("ubuntu-26.04-s390x")["arch"] == "s390x"
    assert parse("ubuntu-24.04-ppc64le-2xlarge-p10")["profile"] == "container"
    assert parse("ubuntu-22.04-x64")["arch"] == "x86_64"
    assert parse("ubuntu-latest-ppc64le")["os"] == "latest"
    for bad in ("ubuntu-24.04", "ubuntu-24.04-arm", "self-hosted", "ubuntu-24.04-vm"):
        try:
            parse(bad)
            raise AssertionError(f"{bad} parsed")
        except PlanError:
            pass
    # checkboxes and typed labels add up, in order, without duplicates
    labels, src = select({"suite": "all", "ubuntu-24_04-ppc64le": True, "ubuntu-22_04-s390x": False,
                          "ubuntu-24_04-ppc64le-p10": "true",
                          "labels": "ubuntu-26.04-ppc64le-vm, ubuntu-24.04-ppc64le\n", "instances": "1"})
    assert labels == ["ubuntu-24.04-ppc64le", "ubuntu-24.04-ppc64le-p10", "ubuntu-26.04-ppc64le-vm"], labels
    assert src == "the run form"
    # nothing selected: the repository variable, else a clear error
    assert select({"ubuntu-24_04-s390x": False, "labels": ""}, "ubuntu-24.04-s390x") == (
        ["ubuntu-24.04-s390x"], "the RUNNER_LABELS repository variable")
    try:
        select({"labels": " "}, "")
        raise AssertionError("empty selection accepted")
    except PlanError as e:
        assert "RUNNER_LABELS" in str(e)
    out, parsed = plan(labels, 2)
    c, v = json.loads(out["container"])["include"], json.loads(out["vm"])["include"]
    assert [(j["label"], j["instance"]) for j in c] == [
        ("ubuntu-24.04-ppc64le", 1), ("ubuntu-24.04-ppc64le", 2),
        ("ubuntu-24.04-ppc64le-p10", 1), ("ubuntu-24.04-ppc64le-p10", 2)], c
    assert v == [{"label": "ubuntu-26.04-ppc64le-vm", "arch": "ppc64le", "os": "26.04", "instance": 1},
                 {"label": "ubuntu-26.04-ppc64le-vm", "arch": "ppc64le", "os": "26.04", "instance": 2}], v
    assert len(json.loads(out["hosted"])["include"]) == 4
    assert out["labels"] == "ubuntu-24.04-ppc64le,ubuntu-24.04-ppc64le-p10,ubuntu-26.04-ppc64le-vm"
    # a profile with no label yields no matrix, so its suite jobs are skipped
    assert plan(["ubuntu-24.04-ppc64le-p10"], 1)[0]["vm"] == ""
    try:
        plan(["ubuntu-24.04-ppc64le", "ubuntu-22.04-ppc64le"], 200)
        raise AssertionError("over 256 jobs accepted")
    except PlanError:
        pass
    assert "| ubuntu-26.04-ppc64le-vm | vm | ppc64le | 26.04 |" in summary(parsed, src, 2)
    print("plan selftest: OK")
    return 0


def main():
    if "--selftest" in sys.argv:
        return selftest()
    inputs = json.loads(os.environ.get("INPUTS_JSON") or "{}")
    try:
        instances = int(inputs.get("instances") or 1)
        labels, source = select(inputs, os.environ.get("FALLBACK", ""))
        out, parsed = plan(labels, instances)
    except PlanError as e:
        print(f"::error title=Runner labels::{e}")
        return 1
    md = summary(parsed, source, instances)
    print(md)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(md)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            for k, val in out.items():
                f.write(f"{k}={val}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
