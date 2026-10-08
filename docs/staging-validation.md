# Validating staging before production

Every change to the runner platform is deployed to staging first and promoted
to production only after this suite passes against staging. This document is
the procedure: what to run, what must be true before promoting, and what to
record.

"Platform change" means anything under the runners, for example:

- host OS, kernel, or firmware on the Power or Z hosts
- LXD or Incus version, profiles, storage, or network configuration
- the runner image (packages, users, sudo rules, AppArmor/seccomp profiles)
- the GitHub Actions runner version or its install dir (`/opt/runner-cache`)
- provisioning, scheduling, or autoscaling code
- network changes: bridge MTU, DNS, proxy, egress policy

## How the suite reaches staging

Staging runners carry the same labels as production. This repository is
attached only to the **staging** runner group, so every `runs-on` label
resolves to a staging runner.

Before each validation, confirm this repo has no access to the production
runner group (org Settings → Actions → Runner groups). If it did, the load
and stress runs below would execute on production runners.

| Profile   | Labels |
|-----------|--------|
| container | `ubuntu-22.04-ppc64le-p10`, `ubuntu-24.04-ppc64le-p10`, `ubuntu-22.04-s390x`, `ubuntu-24.04-s390x` |
| vm        | `ubuntu-22.04-ppc64le-vm`, `ubuntu-24.04-ppc64le-vm`, `ubuntu-22.04-s390x-vm`, `ubuntu-24.04-s390x-vm` |

## Before you start

1. Deploy the change to staging and write down exactly what is deployed
   (versions, commit, config diff). Results mean nothing without it.
2. Check that staging runners are online for all eight labels. A label with
   no online runner leaves its jobs queued until they time out.
3. If staging has both LXD and Incus hosts, make sure both will receive jobs.
   The run's summary lists which backend served each probe job (see "Probe"
   below).
4. Have the `summary.csv` from the last promotion at hand. It is the
   production baseline for comparing durations and known findings.

## Step 1: full functional run

Actions → **run-all** → Run workflow, on `main`:

| Input          | Value |
|----------------|-------|
| `suite`        | `all` |
| `arch`         | `all` |
| `os`           | `all` |
| `instances`    | `1`   |
| `max_parallel` | `25`  |

This runs every domain (capability, security, stress, probe) on every
container and VM label. Each job is capped at 120 minutes.

## Step 2: load run

The full run checks each label once. The load run checks that the service
holds up when many jobs arrive together, which is how communities use it.

Run once per architecture:

| Input          | ppc64le run | s390x run |
|----------------|-------------|-----------|
| `suite`        | `stress`    | `stress`  |
| `arch`         | `ppc64le`   | `s390x`   |
| `os`           | `all`       | `all`     |
| `instances`    | `100`       | `100`     |
| `max_parallel` | `25`        | `25`      |

Each suite workflow fans out `labels × instances` jobs, and GitHub caps one
matrix at 256 jobs. Two labels × 100 = 200 fits; `arch=all` with 100
instances does not, and the run stops at the setup job with that message.
The container and VM suites run side by side, so peak concurrency is up to
twice `max_parallel`.

The kind-based test (`kube-scale`) only runs on ppc64le VMs; on s390x it
reports `SKIP`. That is expected.

**Capacity sweep (optional).** If the change touches scheduling,
provisioning, or autoscaling, repeat the ppc64le load run with
`max_parallel` at `5`, `10`, `25`, and `50`, and compare p95 durations. The
point where p95 climbs sharply is the current concurrency limit.

## Promotion gate

Promote only when all of the following hold for the full run and the load
runs.

| Check | Required |
|-------|----------|
| `aggregate` job | Green. It fails on any `FAIL`, on any suite job that crashed or was cancelled, and when no results arrived. |
| Coverage | All eight labels appear in the results table. A missing label means its jobs never ran. |
| Security | Every row `PASS` on every label, except known findings listed under "Known findings". |
| Capability | No `FAIL`. `XFAIL` on container rows is expected. |
| Capability `WARN` | Each one explained before promoting (see below). |
| Stress | No `FAIL`. No test's p95 more than 20% slower than the baseline unless explained. |
| Probe | "Sandboxes that ran the probe" shows the virt type and backend staging should be running, on every label. |

**Why a capability `WARN` blocks.** `WARN` means a container can now do
something it could not do before, such as load a kernel module or reach
`/dev/kvm`. On a container runner that usually means the change loosened
isolation. Either the change intended it (write that down) or it is a
regression.

The 20% p95 threshold is a starting point. Tighten it once a few promotions
give you a feel for normal variation.

## Reading the results

**Where to look:**

- **Run summary page, `aggregate` job:** one table for the whole run. Failing
  rows first; columns are domain, test, profile, arch, os, result, runs, p50
  and p95 duration.
- **`summary` artifact** (kept 30 days): the same data as `summary.csv`.
- **`result-<domain>-<profile>-<arch>-<os>-<n>` artifacts** (kept 14 days),
  one per job:
  - `verdict-<domain>.tsv`: one line per test
  - `detail-<domain>.tsv`: one line per individual check, with the reason
  - `logs/<test>.log`: full script output

Artifacts expire, so attach `summary.csv` to the change record. It becomes
the baseline for the next promotion.

**Results:**

| Result  | Meaning | Blocks? |
|---------|---------|---------|
| `PASS`  | Behaved as required on this profile | No |
| `FAIL`  | Did not behave as required | Yes |
| `XFAIL` | Failed where failure is expected (e.g. kernel modules in a container) | No |
| `WARN`  | Succeeded where failure was expected | Needs an explanation |
| `INFO`  | Probe output, never gates | No |
| `SKIP`  | Not applicable on this runner | No |

**Probe.** Below the results table, the `aggregate` summary has a
"Sandboxes that ran the probe" table: profile, arch, os, virt type, and
backend for every probe job. Containers should show `virt=lxc`; VMs
`virt=kvm` or `virt=qemu`. `backend=unknown` means the guest API is disabled
on that instance (`security.devlxd` on LXD, `security.guestapi` on Incus);
it does not fail anything, but then this table cannot prove which backend
ran the job.

**Debugging one test** on a staging runner, without GitHub Actions:

```bash
PROFILE=vm ARCH=ppc64le OS=24.04 RESULT_DIR=/tmp/r \
  bash tests/security/host-escape.sh
cat /tmp/r/detail-security.tsv
```

## When something fails

1. Do not promote.
2. Find the failing rows in the `aggregate` table, then the reason in that
   job's `detail-*.tsv` and `logs/`.
3. Rule out a flake: dispatch a new run narrowed to the failure with `suite`,
   `arch`, and `os`. A test that fails twice is a regression.
4. Open an issue with the run link, the failing rows, and the change under
   test. Fix in staging and repeat from Step 1.

A crashed or cancelled suite job (runner lost, setup error, timeout) fails
the gate even when no `FAIL` row appears. Treat it like a failure: the
results table is incomplete.

## Known findings

These can fail on today's platform independently of the change you are
promoting. A known finding that is also in the baseline does not block on
its own, but it needs a tracking issue. Any of these appearing **new** in
staging blocks.

- **`security/secret-leak`, `cred-read`.** Jobs run as the runner user with
  passwordless sudo, so they can read the runner's credential files under
  `/opt/runner-cache`. A job that steals them could register a rogue runner
  and receive other communities' jobs. Passes only when long-lived
  credentials are not on disk in the sandbox, e.g. ephemeral or JIT runners.
- **`security/egress-abuse`, `mining-egress`.** Fails when outbound traffic
  to known crypto-mining pools is not blocked.
- **`security/host-escape`, `sandbox-type` on VMs.** Expects `kvm` or `qemu`
  from `systemd-detect-virt --vm`. If a VM legitimately reports something
  else, add that value to `tests/security/host-escape.sh` instead of
  ignoring the failure.

## What the suite does not cover yet

- Network isolation between sibling runners on a shared bridge (whether one
  tenant's container can reach another's). Check it manually for changes to
  bridges, ACLs, or network isolation settings.
- A comparison against GitHub-hosted x86/arm runners.

## Sign-off record

Paste this into the change ticket or PR and fill it in:

```
Change under test:
Deployed to staging (versions/commit):
Full run:            <run link>   aggregate: green / red
Load run ppc64le:    <run link>   worst p95 vs baseline:
Load run s390x:      <run link>   worst p95 vs baseline:
Backends covered:    LXD [ ]  Incus [ ]
Capability WARN rows and why:
Known findings carried over (issue links):
summary.csv attached: yes / no
Decision: promote / hold
Approved by:                     Date:
```

## When a new community issue comes in

Add a reproduction before closing the issue, so every later promotion checks
it: one script in `tests/capability/` and one line in its `manifest.tsv`
with the expected result per profile. See "Add a test" in the
[README](../README.md).
