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
| vm        | `ubuntu-22.04-ppc64le-vm`, `ubuntu-24.04-ppc64le-vm` (no s390x VM runners yet) |

Environments serve different label sets, so each run selects its labels on
the **run-all** form (one checkbox per label, plus a free-text `labels` field
for any other `ubuntu-<os>-<arch>[-...][-vm]` label). With nothing selected
the run uses the `RUNNER_LABELS` repository variable. For example, the pentest
environment serves only `ubuntu-24.04-ppc64le` (P9) and
`ubuntu-24.04-ppc64le-p10` (P10), both containers.

## Before you start

1. Deploy the change to staging and write down exactly what is deployed
   (versions, commit, config diff). Results mean nothing without it.
2. Check that staging runners are online for every label you will select. A
   label with no online runner leaves its jobs queued until they time out.
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
| runner labels  | every label the environment serves (the six above for staging) |
| `instances`    | `1`   |
| `max_parallel` | `25`  |

This runs every domain (capability, security, stress, probe) on every
selected container and VM label. Each job is capped at 120 minutes.

## Step 2: load run

The full run checks each label once. The load run checks that the service
holds up when many jobs arrive together, which is how communities use it.

Run once per architecture:

| Input          | ppc64le run | s390x run |
|----------------|-------------|-----------|
| `suite`        | `stress`    | `stress`  |
| runner labels  | the ppc64le labels | the s390x labels |
| `instances`    | `100`       | `100`     |
| `max_parallel` | `25`        | `25`      |

Each suite workflow fans out `labels × instances` jobs per profile, and GitHub
caps one matrix at 256 jobs. Two labels × 100 = 200 fits; three do not, and
the run stops at the `plan` job with that message.
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
| Coverage | Every selected label appears in the results table. The report lists any selected label with no results by name. |
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
  rows first; columns are domain, test, profile, label, result, runs, p50
  and p95 duration. Below it, "What failed and how to fix it" has one entry
  per failing test: the labels, each failed check with its reason, the fix,
  and where the log is. The same entries are annotations on the run page.
- **Each suite job's `Run <domain>` step:** every test's output as a folded
  group, then an unfolded block for each `FAIL`/`WARN` with the failed checks,
  the last log lines and the fix.
- **`summary` artifact** (kept 30 days): the same data as `summary.csv`.
- **`result-<domain>-<profile>-<label>-<n>` artifacts** (kept 14 days),
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
| `PARITY` | Failed, but GitHub-hosted runners fail the same checks | No |
| `KNOWN` | Failed only on accepted known findings (`tests/known-findings.tsv`) or parity checks | No |

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
2. Read the failing test's entry under "What failed and how to fix it" in
   the `aggregate` summary: failed checks, reasons, the fix. For more, expand
   the test's group in the suite job's `Run <domain>` step.
3. Rule out a flake: dispatch a new run narrowed to the failure with `suite`
   and only the failing labels ticked. A test that fails twice is a regression.
4. Open an issue with the run link, the failing rows, and the change under
   test. Fix in staging and repeat from Step 1.

A crashed or cancelled suite job (runner lost, setup error, timeout) fails
the gate even when no `FAIL` row appears. Treat it like a failure: the
results table is incomplete.

## Known findings

The bar is parity with GitHub-hosted runners, which every run measures
(profile `hosted`). A finding that GitHub-hosted shares reads `PARITY` and does
not gate; one that only our runners have stays `FAIL`. These can fail on
today's platform independently of the change you are promoting. A known finding that is also in the baseline does not block on
its own, but it needs a tracking issue. Any of these appearing **new** in
staging blocks.

- **`security/secret-leak`, `cred-read`.** Jobs run as the runner user with
  passwordless sudo, so they can read the runner's credential files under
  `/opt/runner-cache`. GitHub-hosted exposes `.credentials` too (`PARITY`), but
  not `.credentials_rsaparams`, the runner's private key, so that check gates
  as "only here". The listener writes both files whether it is registered with
  `config.sh` or `--jitconfig`, so JIT alone does not remove them. Runners are
  `--ephemeral` in a per-job container, which limits a stolen key to the
  registration of the job that stole it. Accepted as a known finding
  (2026-10-25): `cred-read:.credentials_rsaparams` is listed in
  `tests/known-findings.tsv`, so the test reads `KNOWN` and does not gate. A
  token in the job env (`env-token`) or any new file still `FAIL`s.
- **`security/resource-abuse`, `pids-cap`.** Containers share the host kernel;
  without `limits.processes` a runaway job draws on the host's `threads-max`
  (~570k on the pentest workers), shared by every job on that host. The test
  also runs on VMs and GitHub-hosted, where the job owns its kernel and a
  runaway stops at that VM's `threads-max` (~127k on a hosted 16 GB VM, which
  also sets `ulimit -u` 63795), so hosted rows `PASS` and ours read "only here".
  `limits.processes: "65536"` matches the hosted per-job ceiling and keeps four
  jobs under the host's `threads-max`.
- **`security/egress-abuse`, `mining-egress`.** Fails when outbound traffic
  to known crypto-mining pools is not blocked.
- **`security/host-escape`, `sandbox-type` on VMs.** Expects `kvm` or `qemu`
  from `systemd-detect-virt --vm`. If a VM legitimately reports something
  else, add that value to `tests/security/host-escape.sh` instead of
  ignoring the failure.

### Reproduced from the 2026 X-Force Red retest

Each row below reproduces one finding. Fixes span three repos: this suite
(tests), `actions-deploy` (PowerVS + IBM Z Ansible: profiles, firewall, env),
and `action-runner-image-pz` (the job container image: runner user/groups). A
row flips to `PASS` once its fix reaches the label under test.

- **`security/egress-ports` (9984-1, 9984-3).** Egress to non-build ports
  (IRC/DoT) is open — the channel a callback shell uses. `PARITY` until
  `container_egress_filter` is enabled on the label; then our rows `PASS`
  while hosted stays `FAIL` (non-gating). Fix: opt-in `container_egress_filter`
  (default off) on **both** trees — PowerVS via a firewalld policy
  (`container-egress-filter.policy.xml`), IBM Z via a `GHA_EGRESS` allowlist
  chain in both iptables and ip6tables (`vpc-on-ibm-z`
  `tasks/container_egress_filter.yml`, persisted with netfilter-persistent;
  v6 included because `lxdbr0` has `ipv6.nat`). Both allow the ports builds use
  (22/53/80/123/443, 873, 9418, 11371, 8080, 8443, 5000, 587, 465, 5432, 3306,
  6379, 27017) and reject the rest. `capability/egress-reach` checks that list
  against GitHub-hosted: a port open there but blocked here `FAIL`s as "only
  here", so parity and this row hold together. Applied on provision/rebuild
  (rides the init block), so enabling it on an already-provisioned host needs
  a reprovision.
- **`security/capabilities` (9984-6).** Container keeps host-reaching caps
  (`CAP_SYS_MODULE`/`RAWIO`/`TIME`/`BOOT`). Container-only, no hosted
  reference, so it `FAIL`s until the `lxc.cap.drop` fix reaches the label. Fix
  covers every launch profile on both trees: PowerVS worker (`lxd_init.yml.j2`),
  PowerVS remote/image server (`lxd_remote_server_init.yml.j2`), PowerVS Incus
  (`container_driver.yml`), and IBM Z LXD + Incus preseeds.
- **`security/alg-copy-fail` (9984-5, s390x).** AF_ALG interface reachability
  (CVE-2026-31431). `PASS` while seccomp blocks the AF_ALG socket. GitHub-hosted
  leaves AF_ALG open, so an open socket reads `PARITY`; on ppc64le it is open
  (pentest 2026-10-24) and relies on the patched host kernel. Fix: `actions-deploy` IBM Z
  modprobe blocklist + kernel patch.
- **`security/group-membership` (9984-8).** Job user's container-manager
  groups. `action-runner-image-pz` main still adds the runner user to `lxd` and
  `incus-admin` in every build script (`scripts/{lxd,incus}_{container,vm}.sh`,
  `scripts/vm.sh`), so both read `FAIL` until images built without them reach
  the label (`--tags build_lxd_image`). `group:docker` stays `PARITY` (kept,
  matches GitHub-hosted, needed for docker-in-container jobs).
- **`security/sudo-nopasswd` (9984-4).** Passwordless sudo to root. **Accepted
  as parity** — GitHub-hosted grants it too, and removing it breaks
  `sudo`-using jobs. Reads `PARITY`, does not gate. Revisit only with a
  targeted sudoers design in `action-runner-image-pz`.
- **`probe/session-age` (9984-2).** `INFO`. Runners are ephemeral (one job) and
  the finished container is now reaped after 1h (`LXD_DELETE_GITHUB_RUNNER_CONTAINER_AFTER=1`
  in `actions-deploy` env templates), down from 24h/6h.
- **`probe/devlxd` (9984-7).** `INFO`. The LXD/Incus guest API is **kept on
  purpose**: the suite uses it to report which backend ran each job, and the
  dangerous host-info sub-case (the host kernel ring buffer) is already gated
  by `security/host-escape` (`host-dmesg`). Accepted; revisit if the guest API
  is ever disabled fleet-wide.

## What the suite does not cover yet

- Network isolation between sibling runners on a shared bridge (whether one
  tenant's container can reach another's). Check it manually for changes to
  bridges, ACLs, or network isolation settings.

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
