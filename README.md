# power-z GHA runner test suite

Validation suite for our self-hosted GitHub Actions runner service on IBM
Power (`ppc64le`) and IBM Z (`s390x`), across container and VM profiles.
Works unchanged on LXD and Incus hosts; the `probe/host-info` result records
which backend (`backend=lxd|incus`) and sandbox type ran each job.

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
  plan-labels        turn the selected runner labels into per-profile matrices
  run-suite          run one domain for one profile, upload results
  aggregate-report   merge results into a pass/fail matrix, explain FAILs, gate
.github/workflows/
  run-all.yml        one-click/select entry point (workflow_dispatch)
  _suite.yml         reusable per-profile runner (container | vm | hosted)
```

Workflow YAML must stay flat in `.github/workflows/` (GitHub rule); all test
logic lives in `tests/` and runs without GitHub Actions.

## Promoting a platform change

Validate staging with this suite before anything reaches production. The
procedure, promotion gate, and sign-off record are in
[docs/staging-validation.md](docs/staging-validation.md).

## Run from GitHub

Actions tab → **run-all** → pick:

- `suite`: `all | capability | security | stress | probe`
- **runner labels**: tick every label the target environment serves (one
  checkbox per label: `ubuntu-22.04/24.04/26.04` × `ppc64le`, `ppc64le-p10`,
  `ppc64le-vm`, `s390x`). Staging, prod and pentest serve different sets, so
  tick only what that environment has: a job on a label no runner serves sits
  queued until GitHub cancels it, and the aggregate waits for it.
- `labels`: any other labels, comma-separated, e.g.
  `ubuntu-24.04-ppc64le-2xlarge-p10, ubuntu-24.04-s390x-vm`. Profile, arch and
  OS are read from the name (`ubuntu-<os>-<arch>[-...][-vm]`; `-vm` = VM
  profile, anything else = container), so a new Ubuntu version or label needs
  no workflow edit.
- `instances`: copies of every job, to load the service (default `1`)
- `max_parallel`: simultaneous jobs per suite (default `25`)

Nothing ticked or typed runs the labels in the `RUNNER_LABELS` repository
variable (Settings → Secrets and variables → Actions → Variables), e.g.
`ubuntu-24.04-ppc64le,ubuntu-24.04-ppc64le-p10` for the pentest environment.
Set it once per repository attached to an environment, then a plain
**Run workflow** tests exactly that environment. The `plan` job's summary lists
the labels it resolved and the profile/arch/os it read from each.

The aggregate job prints a per `domain × test × profile × label` matrix
(status counts plus p50/p95 script duration) and fails if any check is `FAIL`,
if any suite job crashed or was cancelled, or if no results arrived at all.
Selected labels that produced no results are listed by name.

**What failed and how to fix it.** Below the matrix, every `FAIL` gets its own
entry: the labels it failed on, each failed check with the reason the test
gave, how to fix it (the manifest's `fix` column), and where its log is. The
same text is an annotation on the run page. In each suite job, the `Run <domain>`
step shows every test's output as a folded group, followed by an unfolded
block for each `FAIL`/`WARN` with the failed checks, the last lines of the log
and the fix; the job summary repeats those blocks. Full logs are also in the
`result-<domain>-<profile>-<label>-<n>` artifact under `logs/`.

**Parity with GitHub-hosted.** Every run also executes capability, security,
and probe on GitHub-hosted `ubuntu-22.04`/`24.04` (x86_64 and arm) as profile
`hosted`. Those rows are the reference and never gate. One of our `FAIL`s
becomes `PARITY` (not gating) when every check it failed also failed on every
hosted runner that ran the test: we expose nothing GitHub-hosted does not.

Service load test: `suite=stress`, tick one or two labels, `instances=100`,
`max_parallel=25`. GitHub caps a matrix at 256 jobs, so per profile
`labels × instances` must stay ≤ 256; the `plan` job stops with that message
otherwise.

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
id   script   profiles   expected_container   expected_vm   issue   fix
```

- `profiles`: comma list the test applies to (`container,vm`).
- `expected_<profile>`: `PASS` (must succeed), `XFAIL` (expected to fail here —
  failing is healthy, succeeding is a WARN), `INFO` (never gates), `-` (n/a → SKIP).
- Security rows are always `PASS`: a breach makes the script exit non-zero → `FAIL`.
- `fix`: what to change when the test fails, shown with every `FAIL` in the job
  log and the aggregate report. Name the setting and where it lives (repo, file,
  Ansible tag), not just the symptom. `-` when there is nothing to fix (`INFO`).

Verdict vocabulary: `PASS FAIL XFAIL WARN INFO SKIP PARITY`. Only `FAIL` fails the gate.

## Add a test

1. Drop `tests/<domain>/<id>.sh` (source `assert.sh`, end with `assert_finish`).
   If the test cannot apply on some runner (wrong arch, tool missing), call
   `skip_test "<id>" "<reason>"` so it reports `SKIP` rather than a false
   `PASS` or `WARN`. Clean up any `mktemp` dirs with an `EXIT` trap.
2. Add one line to `tests/<domain>/manifest.tsv`, with its `fix`.

No workflow edits. A new label needs none either: type it into `labels`, or add
a checkbox for it in `run-all.yml` if it is used often.

## Self-checks

```bash
bash tests/lib/assert.sh --selftest
bash tests/lib/runner.sh --selftest
python3 .github/actions/aggregate-report/summarize.py --selftest
python3 .github/actions/plan-labels/plan.py --selftest
```
