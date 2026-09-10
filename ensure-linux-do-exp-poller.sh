#!/bin/sh
set -eu

APP_DIR="${HOME}/slurm-gha"
PID_FILE="${APP_DIR}/slurm-gha-linux-do-exp.pid"
LOCK_FILE="${APP_DIR}/slurm-gha-linux-do-exp.lock"
POLLER_LOG="${APP_DIR}/logs/poller-linux-do-exp.log"
WATCHDOG_LOG="${APP_DIR}/logs/poller-linux-do-exp-watchdog.log"

mkdir -p "${APP_DIR}/logs/linux-do-exp" "${APP_DIR}/gha-runners"

(
    flock -n 9 || exit 0
    cd "${APP_DIR}"

    if [ -f "${PID_FILE}" ]; then
        pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            cmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
            cwd="$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)"
            if [ "${cwd}" = "${APP_DIR}" ] && echo "${cmd}" | grep -q "main.py"; then
                exit 0
            fi
        fi
    fi

    printf '%s restarting linux-do experimental poller\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${WATCHDOG_LOG}"
    nohup /bin/bash -lc '
      set -e
      cd /home/xihuang/slurm-gha
      if [ -f /etc/profile.d/spur.sh ]; then
        . /etc/profile.d/spur.sh
      fi
      if [ -z "${SPUR_CONTROLLER_ADDR:-}" ]; then
        export SPUR_CONTROLLER_ADDR="http://10.245.149.59:6817,http://10.245.145.205:6817,http://10.245.149.95:6817"
      fi
      export SLURM_CLUSTER_PROFILES_FILE=/home/xihuang/slurm-gha/cluster_profiles.local.json
      export SLURM_CLUSTER_PROFILE=spur-di
      export RESOURCE_LABEL_PREFIX=__disabled_for_linux_do_exp__
      export RESOURCE_LABEL_ALIASES=linux-atom-do-mi350x-8=slurm-runner-mi355x-8gpu
      export RESOURCE_LABEL_CAPS=linux-atom-do-mi350x-8=6
      export SLURM_LOG_DIR=logs/linux-do-exp
      export GHA_RUNNER_WORK_ROOT=/home/xihuang/slurm-gha/gha-runners
      export THREAD_SLEEP_TIMEOUT=10
      exec .venv/bin/python main.py
    ' </dev/null >> "${POLLER_LOG}" 2>&1 &
    echo "$!" > "${PID_FILE}"
) 9>"${LOCK_FILE}"
