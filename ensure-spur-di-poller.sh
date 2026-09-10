#!/bin/sh
set -eu

APP_DIR="${HOME}/slurm-gha"
PID_FILE="${APP_DIR}/slurm-gha-spur-di.pid"
LOCK_FILE="${APP_DIR}/slurm-gha-spur-di.lock"
POLLER_LOG="${APP_DIR}/logs/poller-spur-di.log"
WATCHDOG_LOG="${APP_DIR}/logs/poller-watchdog.log"

mkdir -p "${APP_DIR}/logs"

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

    printf '%s restarting spur-di poller\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${WATCHDOG_LOG}"
    nohup ./run-spur-di.sh </dev/null >> "${POLLER_LOG}" 2>&1 &
    echo "$!" > "${PID_FILE}"
) 9>"${LOCK_FILE}"
