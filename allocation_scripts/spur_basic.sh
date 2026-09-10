#!/bin/bash
# Use: spur_basic.sh <repo-url> <registration-token> <removal-token> <labels> <github-job-id>

set -euo pipefail

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') $*"
}

if [ "$#" -lt 4 ]; then
    log "ERROR: Missing required arguments"
    log "Usage: $0 <repo-url> <registration-token> <removal-token> <labels> [github-job-id]"
    exit 1
fi

REPO_URL=$1
REGISTRATION_TOKEN=$2
REMOVAL_TOKEN=$3
LABELS=$4
GITHUB_JOB_ID=${5:-unknown}

RUNNER_PLATFORM=${ACTIONS_RUNNER_PLATFORM:-linux-x64}
RUNNER_VERSION=${ACTIONS_RUNNER_VERSION:-latest}
RUNNER_ROOT=${GHA_RUNNER_WORK_ROOT:-${TMPDIR:-/tmp}/gha-runners}
SLURM_ID=${SLURM_JOB_ID:-$$}
RUNNER_DIR="${RUNNER_ROOT}/runner-${SLURM_ID}-${GITHUB_JOB_ID}"
WORK_DIR="${RUNNER_DIR}/_work"

if [ "$RUNNER_VERSION" = "latest" ] && [ -z "${ACTIONS_RUNNER_TARBALL:-}" ]; then
    RUNNER_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        https://github.com/actions/runner/releases/latest | sed 's#^.*/v##')
fi

TARBALL="actions-runner-${RUNNER_PLATFORM}-${RUNNER_VERSION}.tar.gz"
TARBALL_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"
RUNNER_NAME="spur-${SLURM_ID}-${GITHUB_JOB_ID}"

cleanup() {
    set +e
    if [ -d "$RUNNER_DIR" ]; then
        cd "$RUNNER_DIR" || exit 0
        if [ -x ./config.sh ]; then
            log "Removing GitHub Actions runner ${RUNNER_NAME}"
            ./config.sh remove --token "$REMOVAL_TOKEN"
        fi
        cd /
        rm -rf "$RUNNER_DIR"
    fi
}
trap cleanup EXIT INT TERM

log "Preparing GitHub Actions runner ${RUNNER_NAME}"
mkdir -p "$WORK_DIR"
cd "$RUNNER_DIR"

if [ -n "${ACTIONS_RUNNER_TARBALL:-}" ]; then
    log "Using local runner tarball ${ACTIONS_RUNNER_TARBALL}"
    tar xzf "$ACTIONS_RUNNER_TARBALL"
else
    log "Downloading ${TARBALL_URL}"
    curl -fsSL -o "$TARBALL" "$TARBALL_URL"
    tar xzf "$TARBALL"
fi

export RUNNER_ALLOW_RUNASROOT=${RUNNER_ALLOW_RUNASROOT:-1}

# The Slurm job inherits the controller environment by default. Do not expose
# controller credentials to the GitHub Actions job environment.
unset GITHUB_APP_ID
unset GITHUB_APP_INSTALLATION_ID
unset GITHUB_APP_PRIVATE_KEY_PATH
unset GITHUB_ACCESS_TOKEN

log "Registering runner ${RUNNER_NAME} with labels ${LABELS}"
./config.sh \
    --work "$WORK_DIR" \
    --url "$REPO_URL" \
    --token "$REGISTRATION_TOKEN" \
    --labels "$LABELS" \
    --name "$RUNNER_NAME" \
    --unattended \
    --ephemeral \
    --disableupdate

log "Starting runner ${RUNNER_NAME}"
IDLE_TIMEOUT_SECONDS=${SPUR_RUNNER_IDLE_TIMEOUT_SECONDS:-600}
RUNNER_OUTPUT="${RUNNER_DIR}/runner-output.log"
set +e
./run.sh > >(tee -a "${RUNNER_OUTPUT}") 2>&1 &
runner_pid=$!
(
    slept=0
    while kill -0 "${runner_pid}" 2>/dev/null; do
        if grep -q "Running job:" "${RUNNER_OUTPUT}" 2>/dev/null; then
            exit 0
        fi
        if [ "${slept}" -ge "${IDLE_TIMEOUT_SECONDS}" ]; then
            log "Runner ${RUNNER_NAME} was idle for ${IDLE_TIMEOUT_SECONDS}s. Stopping it."
            kill "${runner_pid}" 2>/dev/null || true
            sleep 10
            kill -9 "${runner_pid}" 2>/dev/null || true
            exit 0
        fi
        sleep 5
        slept=$((slept + 5))
    done
) &
idle_watchdog_pid=$!
wait "${runner_pid}"
runner_rc=$?
kill "${idle_watchdog_pid}" 2>/dev/null || true
set -e
log "Runner ${RUNNER_NAME} finished with rc=${runner_rc}"
exit "${runner_rc}"
