# Spur DI Slurm GHA Poller Runbook

Last updated: 2026-09-02

This documents the `slurm-gha` deployment on the Crusoe Spur login node for
running GitHub Actions jobs through short-lived Slurm allocations.

## Deployment

- Login node: `crs-m2m-cpu-spur-009.crusoe.amd.com`
- Install path: `/home/xihuang/slurm-gha`
- Branch: `spur-mvp`
- Poller PID file: `/home/xihuang/slurm-gha/slurm-gha-spur-di.pid`
- Poller log: `/home/xihuang/slurm-gha/logs/poller-spur-di.log`
- Watchdog log: `/home/xihuang/slurm-gha/logs/poller-watchdog.log`

The poller monitors:

```env
GHA_REPOS=ROCm/ATOM,gyohuangxin/slurm-gha
```

## Slurm Account And QoS

The deployment uses a local cluster profile file:

```text
/home/xihuang/slurm-gha/cluster_profiles.local.json
```

The active profile is `spur-di`:

```json
{
  "spur-di": {
    "description": "Crusoe Spur cluster using the amd-aifw-di Slurm account",
    "sbatch_extra_args": [
      "--partition=amd-spur",
      "--account=amd-aifw-di",
      "--qos=amd-aifw-di-qos"
    ]
  }
}
```

The launcher script is:

```text
/home/xihuang/slurm-gha/run-spur-di.sh
```

It exports:

```sh
SLURM_CLUSTER_PROFILES_FILE=/home/xihuang/slurm-gha/cluster_profiles.local.json
SLURM_CLUSTER_PROFILE=spur-di
RESOURCE_LABEL_PREFIX=spur-runner
```

## Label Contract

Use the `spur-runner-*` labels for jobs that should be handled by this Slurm
poller. Do not reuse existing shared runner pool labels by themselves.

Recommended labels:

```yaml
runs-on: [self-hosted, spur-runner-mi355x-1gpu]
runs-on: [self-hosted, spur-runner-mi355x-8gpu]
```

The `runner_size_config.py` helper normalizes `spur-runner-*` to the existing
`slurm-runner-*` resource table internally. For example:

```text
spur-runner-mi355x-8gpu -> --gres=gpu:mi355x:8 --cpus-per-task=128 --mem-per-cpu=2G --time=00:30:00
```

Keep `spur-runner-*` exclusive to this poller. If an existing long-lived runner
also has the same label, GitHub can assign the job to either runner, and the
poller can waste Slurm allocations.

## Watchdog

The watchdog script is:

```text
/home/xihuang/slurm-gha/ensure-spur-di-poller.sh
```

It uses `flock` and `slurm-gha-spur-di.pid` to avoid duplicate poller processes.
If the PID is missing or dead, it restarts:

```sh
nohup ./run-spur-di.sh </dev/null >> logs/poller-spur-di.log 2>&1 &
```

Crontab entries:

```cron
*/10 * * * * /home/xihuang/slurm-gha/ensure-spur-di-poller.sh >> /home/xihuang/slurm-gha/logs/poller-watchdog.log 2>&1
@reboot /home/xihuang/slurm-gha/ensure-spur-di-poller.sh >> /home/xihuang/slurm-gha/logs/poller-watchdog.log 2>&1
```

## Common Commands

Check the poller:

```sh
cd /home/xihuang/slurm-gha
ps -p "$(cat slurm-gha-spur-di.pid)" -o pid,ppid,stat,etime,cmd
tail -f logs/poller-spur-di.log
```

Restart manually:

```sh
cd /home/xihuang/slurm-gha
kill "$(cat slurm-gha-spur-di.pid)" 2>/dev/null || true
./ensure-spur-di-poller.sh
```

Check the watchdog:

```sh
crontab -l | grep ensure-spur-di-poller.sh
tail -f /home/xihuang/slurm-gha/logs/poller-watchdog.log
```

Check Slurm jobs submitted by the poller:

```sh
squeue -u "$(whoami)" -o "%.18i %.9P %.46j %.12A %.18q %.2t %.10M %.20b %.40R"
```

Inspect a Slurm runner allocation:

```sh
spur show job <slurm-job-id>
tail -160 /home/xihuang/slurm-gha/logs/gha-<slurm-job-id>.out
cat /home/xihuang/slurm-gha/spur-<slurm-job-id>.out
```

Check GitHub jobs:

```sh
gh pr checks 2005 --repo ROCm/ATOM --watch=false
gh api repos/ROCm/ATOM/actions/jobs/<github-job-id> \
  --jq '{id,status,conclusion,runner_name,runner_id,labels}'
```

## Troubleshooting Notes

- A queued GitHub job with `runner_id=0` has not been assigned to a runner yet.
- A Slurm job that reaches `Listening for Jobs` but is then `CANCELLED` usually
  means the runner was terminated before GitHub assigned the job.
- Earlier 8GPU retries repeatedly landed on `crsuse2-m2m-096` and were cancelled
  within seconds. A later retry on a stable allocation succeeded.
- If a specific node repeatedly terminates allocations, temporarily add an
  exclude through `SBATCH_EXTRA_ARGS`, for example:

```env
SBATCH_EXTRA_ARGS=--exclude=crsuse2-m2m-096
```

Restart the poller after changing `.env`.

## Current Known Good Result

PR `ROCm/ATOM#2005` successfully ran the 8GPU accuracy job with:

```text
GitHub job: 99797093995
Runner: spur-95262-99797093995
Label: spur-runner-mi355x-8gpu
Result: success
Duration: 7m18s
```
