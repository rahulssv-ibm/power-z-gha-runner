# power-z GHA runner test suite

Validation suite for our self-hosted GitHub Actions runner service on IBM
Power (`ppc64le`) and IBM Z (`s390x`), across container and VM profiles.

## Layout

```
tests/
  lib/assert.sh      result helpers (ok/fail/xfail/skip/expect_ok/expect_blocked)
  lib/runner.sh      engine: runs a domain's manifest, writes verdicts, gates
  capability/        community issue repros (falco, kata, kind, overlayfs, ...)
  security/          sandbox-integrity: tenant isolation must hold
  stress/            cpu/mem/disk/kube/network/build load
  probe/             informational host snapshots
.github/actions/
  setup-kind-ppc64le build+install Go/kind/kubectl
  run-suite          run one domain for one profile, upload results
  aggregate-report   merge results into a pass/fail matrix, gate on FAIL
.github/workflows/
  run-all.yml        one-click/select entry point (workflow_dispatch)
  _suite-container.yml / _suite-vm.yml  reusable per-profile runners
```

Workflow YAML must stay flat in `.github/workflows/` (GitHub rule); all test
logic lives in `tests/` and runs without GitHub Actions.

## Run from GitHub

Actions tab → **run-all** → pick:

- `suite`: `all | container | vm | capability | security | stress | probe`
- `arch`: `all | ppc64le | s390x`
- `os`: `all | 22.04 | 24.04`
- `instances`: copies of every job, to load the service (default `1`)
- `max_parallel`: simultaneous jobs per suite (default `25`)

One click (`all`) runs every domain on both profiles. The aggregate job prints
a per `arch × os × profile × domain` matrix (status counts plus p50/p95 script
duration) and fails if any check is `FAIL`, if any suite job crashed or was
cancelled, or if no results arrived at all.

Service load test (replaces the old 200-job kind stress): `suite=stress`,
`arch=ppc64le`, `os=24.04`, `instances=200`, `max_parallel=25`. GitHub caps a
matrix at 256 jobs, so `labels × instances` must stay ≤ 256 — narrow `arch`/`os`
for high instance counts.

## Run one test locally

```bash
PROFILE=vm ARCH=ppc64le OS=24.04 RESULT_DIR=/tmp/r \
  bash tests/capability/kvm.sh
cat /tmp/r/detail-capability.tsv

# or a whole domain through the engine:
PROFILE=container ARCH=s390x OS=24.04 RESULT_DIR=/tmp/r \
  bash tests/lib/runner.sh security
cat /tmp/r/verdict-security.tsv
```

## Manifest schema

`tests/<domain>/manifest.tsv`, tab-separated:

```
id   script   profiles   expected_container   expected_vm   issue
```

- `profiles`: comma list the test applies to (`container,vm`).
- `expected_<profile>`: `PASS` (must succeed), `XFAIL` (expected to fail here —
  failing is healthy, succeeding is a WARN), `INFO` (never gates), `-` (n/a → SKIP).
- Security rows are always `PASS`: a breach makes the script exit non-zero → `FAIL`.

Verdict vocabulary: `PASS FAIL XFAIL WARN INFO SKIP`. Only `FAIL` fails the gate.

## Add a test

1. Drop `tests/<domain>/<id>.sh` (source `assert.sh`, end with `assert_finish`).
2. Add one line to `tests/<domain>/manifest.tsv`.

No workflow edits. New arch/os = one matrix line in the suite workflow.

## Self-checks

```bash
bash tests/lib/assert.sh --selftest
bash tests/lib/runner.sh --selftest
python3 .github/actions/aggregate-report/summarize.py --selftest
```
