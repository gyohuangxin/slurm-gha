#!/bin/sh
set -eu

cd "$(dirname "$0")"

if [ -f /etc/profile.d/spur.sh ]; then
    . /etc/profile.d/spur.sh
fi
if [ -z "${SPUR_CONTROLLER_ADDR:-}" ]; then
    export SPUR_CONTROLLER_ADDR="http://10.245.149.59:6817,http://10.245.145.205:6817,http://10.245.149.95:6817"
fi

export SLURM_CLUSTER_PROFILES_FILE="$PWD/cluster_profiles.local.json"
export SLURM_CLUSTER_PROFILE="spur-di"
export RESOURCE_LABEL_PREFIX="spur-runner"
export RESOURCE_LABEL_CAPS="${RESOURCE_LABEL_CAPS:-spur-runner-mi355x-8gpu=3}"
export SBATCH_EXTRA_ARGS="${SBATCH_EXTRA_ARGS:-}"

exec .venv/bin/python main.py
