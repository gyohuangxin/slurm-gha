# Spur Poller Runbook

This runbook records the current Spur login node deployment and the runner cap
setup used for ATOM CI.

## Current Deployment

Use the stable login alias:

```bash
ssh crs-m2m-cpu-spur-login.crusoe.amd.com
```

At the time of setup, this alias landed on:

```text
crs-m2m-cpu-spur-013
```

The poller repo is expected at:

```text
/home/xihuang/slurm-gha
```

The Spur controller environment must be loaded before calling `sbatch`,
`squeue`, or `scontrol`:

```bash
. /etc/profile.d/spur.sh
scontrol ping
```

Expected controller on older login nodes:

```text
SPUR_CONTROLLER_ADDR=http://crs-m2m-cpu-spur-005.crusoe.amd.com:6817
```

On the newer `crs-spur.crusoe.amd.com` login alias, `/etc/profile.d/spur.sh`
may not exist. The checked-in startup scripts fall back to:

```text
SPUR_CONTROLLER_ADDR=http://10.245.149.59:6817,http://10.245.145.205:6817,http://10.245.149.95:6817
```

## Pollers

There are two pollers.

The main poller handles native Spur labels:

```text
RESOURCE_LABEL_PREFIX=spur-runner
RESOURCE_LABEL_CAPS=spur-runner-mi355x-8gpu=3
```

It should only create at most 3 live Slurm jobs whose names start with:

```text
gha-spur-runner-mi355x-8gpu-
```

The experimental poller lets Spur also serve the existing DO ARC label:

```text
RESOURCE_LABEL_PREFIX=__disabled_for_linux_do_exp__
RESOURCE_LABEL_ALIASES=linux-atom-do-mi350x-8=slurm-runner-mi355x-8gpu
RESOURCE_LABEL_CAPS=linux-atom-do-mi350x-8=6
SLURM_LOG_DIR=logs/linux-do-exp
GHA_RUNNER_WORK_ROOT=/home/xihuang/slurm-gha/gha-runners
```

It should only create at most 6 live Slurm jobs whose names start with:

```text
gha-linux-atom-do-mi350x-8-
```

## Important Scheduling Behavior

GitHub self-hosted runners are assigned by label, not by job id.

The poller may submit a Slurm runner after seeing GitHub job `A`, but once that
runner registers with label `linux-atom-do-mi350x-8` or
`spur-runner-mi355x-8gpu`, GitHub can assign any queued job with the same label.
The job id in the runner name is only a hint for debugging.

Example:

```text
runner name: spur-125017-102374132020
runner label: linux-atom-do-mi350x-8
actual GitHub job: any queued job with linux-atom-do-mi350x-8
```

## Why Caps Are Needed

The DO ARC runner scale set and the Spur experimental poller can both listen to:

```text
linux-atom-do-mi350x-8
```

GitHub will assign each job to only one runner, but both systems can scale out at
the same time. The runner that does not receive a job may sit idle.

For ARC, idle pods normally scale down because `minRunners=0`.

For Spur, an idle Slurm runner still holds an 8 GPU allocation until it receives
a job or reaches the Slurm time limit. Therefore the Spur side must be capped.

Current caps:

```text
spur-runner-mi355x-8gpu: 3
linux-atom-do-mi350x-8: 6
```

The shared MI355X 8 GPU runner resource uses:

```text
Slurm walltime: 01:00:00
Idle timeout before receiving a GitHub job: 600 seconds
```

The idle timeout only applies while the runner is still waiting for a job. Once
`Running job:` appears in the GitHub runner output, the idle watchdog stops and
the job can use the remaining Slurm walltime.

## Implementation Notes

`config.py` supports environment controlled label aliases and caps:

```bash
RESOURCE_LABEL_ALIASES=linux-atom-do-mi350x-8=slurm-runner-mi355x-8gpu
RESOURCE_LABEL_CAPS=linux-atom-do-mi350x-8=6
```

`main.py` enforces caps by checking both:

```text
1. short pre-submit in-process allocations
2. live Slurm jobs from squeue
```

This avoids stale in-memory state blocking new runners after a Slurm job has
already finished.

The main poller default cap is set in `run-spur-di.sh`:

```bash
export RESOURCE_LABEL_CAPS="${RESOURCE_LABEL_CAPS:-spur-runner-mi355x-8gpu=3}"
```

The experimental poller cap is set in `ensure-linux-do-exp-poller.sh`:

```bash
export RESOURCE_LABEL_ALIASES=linux-atom-do-mi350x-8=slurm-runner-mi355x-8gpu
export RESOURCE_LABEL_CAPS=linux-atom-do-mi350x-8=6
```

The startup scripts are checked into the repo:

```text
run-spur-di.sh
ensure-spur-di-poller.sh
ensure-linux-do-exp-poller.sh
scripts/install-spur-poller-crontab.sh
```

## Watchdogs And Crontab

Install the crontab on the active login node:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
*/10 * * * * /bin/bash -lc '/home/xihuang/slurm-gha/ensure-spur-di-poller.sh >> /home/xihuang/slurm-gha/logs/poller-watchdog.log 2>&1'
@reboot /bin/bash -lc '/home/xihuang/slurm-gha/ensure-spur-di-poller.sh >> /home/xihuang/slurm-gha/logs/poller-watchdog.log 2>&1'
*/10 * * * * /bin/bash -lc '/home/xihuang/slurm-gha/ensure-linux-do-exp-poller.sh >> /home/xihuang/slurm-gha/logs/poller-linux-do-exp-watchdog.log 2>&1'
@reboot /bin/bash -lc '/home/xihuang/slurm-gha/ensure-linux-do-exp-poller.sh >> /home/xihuang/slurm-gha/logs/poller-linux-do-exp-watchdog.log 2>&1'
```

## Deploy On A New Login Node

1. Log in through the stable alias.

```bash
ssh crs-m2m-cpu-spur-login.crusoe.amd.com
cd /home/xihuang/slurm-gha
```

2. Confirm Spur controller access.

```bash
. /etc/profile.d/spur.sh
echo "$SPUR_CONTROLLER_ADDR"
scontrol ping
```

3. Move stale PID and lock files if they point to a dead process from another
   login node.

```bash
ts=$(date -u '+%Y%m%dT%H%M%SZ')
for base in slurm-gha-spur-di slurm-gha-linux-do-exp; do
  [ -f "${base}.pid" ] && mv "${base}.pid" "${base}.pid.stale.${ts}"
  [ -f "${base}.lock" ] && mv "${base}.lock" "${base}.lock.stale.${ts}"
done
```

4. Start both pollers.

```bash
/bin/bash -lc '/home/xihuang/slurm-gha/ensure-spur-di-poller.sh >> /home/xihuang/slurm-gha/logs/poller-watchdog.log 2>&1'
/bin/bash -lc '/home/xihuang/slurm-gha/ensure-linux-do-exp-poller.sh >> /home/xihuang/slurm-gha/logs/poller-linux-do-exp-watchdog.log 2>&1'
```

5. Install the crontab.

```bash
./scripts/install-spur-poller-crontab.sh
```

## Verify

Check poller processes:

```bash
cd /home/xihuang/slurm-gha
for f in slurm-gha-spur-di.pid slurm-gha-linux-do-exp.pid; do
  echo "$f=$(cat "$f" 2>/dev/null || true)"
  [ -f "$f" ] && ps -p "$(cat "$f")" -o pid,ppid,stat,lstart,etime,cmd
done
```

Check live Slurm runner jobs:

```bash
. /etc/profile.d/spur.sh
squeue -u xihuang -o '%i|%j|%T|%M|%R' | grep -E 'gha-spur-runner|gha-linux-atom-do|JOBID'
```

Check main poller cap behavior:

```bash
grep -a -n 'Skipping job because label spur-runner-mi355x-8gpu already has' \
  /home/xihuang/slurm-gha/logs/poller-spur-di.log | tail
```

Check experimental poller cap behavior:

```bash
grep -a -n 'Skipping job because label linux-atom-do-mi350x-8 already has' \
  /home/xihuang/slurm-gha/logs/poller-linux-do-exp.log | tail
```

Check experimental runner creation:

```bash
grep -a -n 'Allocated runner for job' \
  /home/xihuang/slurm-gha/logs/poller-linux-do-exp.log | tail
ls -lt /home/xihuang/slurm-gha/logs/linux-do-exp/gha-*.out | head
```

## Rollback

Stop the experimental DO label poller only:

```bash
cd /home/xihuang/slurm-gha
pid=$(cat slurm-gha-linux-do-exp.pid 2>/dev/null || true)
[ -n "$pid" ] && kill "$pid"
crontab -l | grep -v 'ensure-linux-do-exp-poller.sh' | crontab -
```

Stop both pollers:

```bash
cd /home/xihuang/slurm-gha
for f in slurm-gha-spur-di.pid slurm-gha-linux-do-exp.pid; do
  pid=$(cat "$f" 2>/dev/null || true)
  [ -n "$pid" ] && kill "$pid"
done
crontab -r
```

Cancel active Slurm GHA runners if needed:

```bash
. /etc/profile.d/spur.sh
squeue -u xihuang -o '%i|%j|%T' | awk -F'|' '/^125|gha-/ {print}'
scancel <job_id>
```

## Known Pitfalls

If `SPUR_CONTROLLER_ADDR` is not loaded, Spur CLI defaults to:

```text
http://localhost:6817
```

Then `sbatch` fails with:

```text
failed to connect to spurctld
Connection refused
```

Always source `/etc/profile.d/spur.sh` in non-interactive scripts.

If a poller says `already has 1/1` or `already has 3/3` while `squeue` shows no
matching live Slurm jobs, restart that poller. This indicates stale in-memory
allocation state from a missed terminal status.
