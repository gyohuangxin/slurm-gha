# run-gha-on-slurm

[Check out the blog post](https://cloud.watonomous.ca/blog/using-slurm-to-run-github-actions)

The purpose of this project is to run GitHub Actions on prem via our Slurm cluster.

## Spur / Slurm MVP quickstart

This fork includes a minimal polling-based setup for running GitHub Actions jobs on
a Spur or Slurm cluster without reserving nodes ahead of time. A lightweight Python
process runs on a login/head node, polls GitHub for queued workflow jobs, and submits
one short-lived `sbatch` job for each matching queued job. The batch job registers an
ephemeral GitHub Actions runner, runs one job, then exits and cleans up.

### Flow

```mermaid
flowchart TD
    A[GitHub Actions job queued] --> B{Job labels include slurm-runner-*?}
    B -- No --> C[Leave job queued for other runners]
    B -- Yes --> D[Poller maps label to resources]
    D --> E[Create repo runner registration and removal tokens]
    E --> F[Submit short Spur/Slurm job with sbatch]
    F --> G[Spur schedules a compute node]
    G --> H[spur_basic.sh starts on allocated node]
    H --> I[Download or unpack GitHub Actions runner]
    I --> J[Register ephemeral self-hosted runner with same labels]
    J --> K[GitHub assigns a matching queued job to the runner]
    K --> L[Runner executes workflow steps]
    L --> M[Runner exits after one job]
    M --> N[Cleanup runner registration and work directory]
    N --> O[Spur/Slurm allocation ends]

    P[GitHub App private key] --> Q[Installation token]
    Q --> D
    Q --> E
```

The login/head node process is only a controller: it polls GitHub, filters by
labels, and submits `sbatch`. It does not reserve compute nodes while idle. Compute
resources are allocated only after a matching GitHub job is already queued, and
the allocated job runs exactly one ephemeral GitHub Actions runner. GitHub Actions
does not let us bind a runner to a specific job id, so the matching contract is
the `runs-on` label set.

### 1. Install on the login/head node

```bash
git clone https://github.com/gyohuangxin/slurm-gha.git
cd slurm-gha
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Edit `.env`:

```bash
GITHUB_APP_ID=...
GITHUB_APP_INSTALLATION_ID=...
GITHUB_APP_PRIVATE_KEY_PATH=/secure/path/to/app.private-key.pem
GHA_REPOS=owner/repo

# Optional. Only set this if sbatch/sacct are not already in PATH.
SLURM_BIN_DIR=/path/to/spur/bin

# Start simple. Add partition/GPU requests once CPU jobs work.
SBATCH_EXTRA_ARGS="--partition=default"
```

The recommended authentication mode is a GitHub App installed on each repository
in `GHA_REPOS`. Configure the App with repository permissions:

- `Actions`: read and write
- `Administration`: read and write
- `Metadata`: read-only

Then install the App on the target repositories, download the App private key, and
set `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and
`GITHUB_APP_PRIVATE_KEY_PATH` in `.env`.

If your environment permits personal access tokens, `GITHUB_ACCESS_TOKEN` is still
supported as a fallback. GitHub App credentials take over automatically when
`GITHUB_ACCESS_TOKEN` is empty.

Example `.env` for the ROCm Repo Management API 7 GitHub App:

```env
# GitHub App auth
GITHUB_APP_ID=1748281
GITHUB_APP_INSTALLATION_ID=79856739
GITHUB_APP_PRIVATE_KEY_PATH=/home/xihuang/secrets/rocm-repo-api-github-app-7.pem
GITHUB_ACCESS_TOKEN=

# Repositories to monitor. Use commas for multiple repositories.
GHA_REPOS=ROCm/rocOps

# Spur / Slurm
SLURM_BIN_DIR=
SBATCH_EXTRA_ARGS="--partition=default"
SLURM_LOG_DIR=logs

# Poller settings
NETWORK_TIMEOUT=30
SLURM_COMMAND_TIMEOUT=60
THREAD_SLEEP_TIMEOUT=10
RESOURCE_LABEL_PREFIX=slurm-runner
INCLUDE_TMPDISK_GRES=false

# Runner package
ACTIONS_RUNNER_PLATFORM=linux-x64
ACTIONS_RUNNER_VERSION=latest
GHA_RUNNER_WORK_ROOT=/tmp/gha-runners
```

Keep the private key in a separate PEM file rather than embedding it in `.env`:

```bash
mkdir -p ~/secrets
vi ~/secrets/rocm-repo-api-github-app-7.pem
chmod 600 ~/secrets/rocm-repo-api-github-app-7.pem
```

The PEM file should keep the downloaded GitHub App private key as-is:

```text
-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----
```

You can test authentication before starting the poller:

```bash
python3 -c 'from dotenv import load_dotenv; load_dotenv(); from github_auth import GitHubAuth; print(GitHubAuth.from_env().headers()["Authorization"][:24])'
```

Expected output starts with:

```text
Bearer ghs_
```

### 2. Add a workflow that targets the Slurm runner

Use a `slurm-runner-*` label so the poller knows this job should be scheduled on
the cluster:

```yaml
name: spur-smoke

on:
  workflow_dispatch:

jobs:
  smoke:
    runs-on: [self-hosted, slurm-runner-small]
    steps:
      - run: hostname
      - run: env | sort | grep -E 'SLURM|SPUR|RUNNER'
```

The built-in resource labels are:

- `slurm-runner-small`: 1 CPU, 2G per CPU, 30 minutes
- `slurm-runner-medium`: 2 CPUs, 2G per CPU, 30 minutes
- `slurm-runner-large`: 4 CPUs, 2G per CPU, 30 minutes
- `slurm-runner-xlarge`: 16 CPUs, 2G per CPU, 30 minutes
- `slurm-runner-medium-long-running`: 4 CPUs, 2G per CPU, 6 hours

Custom labels are also supported:

```text
slurm-runner-4cpu-8mempercpu-01:00:00time
```

### 3. Run the poller

```bash
. .venv/bin/activate
python main.py
```

When a queued GitHub Actions job has a matching `slurm-runner*` label, the poller
submits an `sbatch --parsable ... allocation_scripts/spur_basic.sh ...` command.
The runner logs are written under `SLURM_LOG_DIR`, which defaults to `logs`.

### 4. GPU / Spur examples

Keep GPU requirements in `SBATCH_EXTRA_ARGS` while you are validating the setup:

```bash
SBATCH_EXTRA_ARGS="--partition=gpu --gres=gpu:mi300x:1"
```

Then use the same GitHub label:

```yaml
runs-on: [self-hosted, slurm-runner-small]
```

After the MVP works, move GPU-specific mappings into `runner_size_config.py` or
split them by labels such as `slurm-runner-mi300x-small`.

### Notes

- GitHub Actions does not have Buildkite-style `--acquire-job <id>` semantics.
  Runners match jobs by labels. Keep labels specific enough that an ephemeral
  runner is unlikely to pick up unrelated work.
- `allocation_scripts/spur_basic.sh` does not start Docker. It is intended for
  smoke tests and workflows that can run directly on the allocated node. Use or
  adapt the Docker/Apptainer allocation scripts if your workflows require Docker
  actions or service containers.
- The default `ACTIONS_RUNNER_VERSION` is configurable in `.env`. You can also
  point `ACTIONS_RUNNER_TARBALL` at a pre-downloaded runner archive if compute
  nodes do not have internet access.
