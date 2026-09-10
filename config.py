import os
import json
import shlex
from pathlib import Path

from dotenv import load_dotenv


load_dotenv()

BASE_DIR = Path(__file__).resolve().parent


def env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "on")


def env_int(name, default):
    value = os.getenv(name)
    if value is None:
        return default
    return int(value)


def parse_key_value_map(name, value_parser=str):
    raw = os.getenv(name, "")
    result = {}
    for item in [part.strip() for part in raw.split(",") if part.strip()]:
        if "=" not in item:
            raise RuntimeError(f"{name} entries must use source=target format: {item!r}")
        key, value = [part.strip() for part in item.split("=", 1)]
        if not key or not value:
            raise RuntimeError(f"{name} entries must not be empty: {item!r}")
        result[key] = value_parser(value)
    return result


def parse_repos():
    repos = os.getenv("GHA_REPOS", os.getenv("GITHUB_REPOSITORY", ""))
    entries = []
    for repo in [item.strip() for item in repos.split(",") if item.strip()]:
        entries.append(
            {
                "name": repo,
                "api_base_url": f"https://api.github.com/repos/{repo}",
                "repo_url": f"https://github.com/{repo}",
            }
        )
    return entries


def load_cluster_profiles():
    profile_file = os.getenv("SLURM_CLUSTER_PROFILES_FILE") or str(
        BASE_DIR / "cluster_profiles.json"
    )

    path = Path(profile_file)
    if not path.exists():
        raise RuntimeError(f"Cluster profile file not found: {profile_file}")

    with path.open(encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict):
        raise RuntimeError(f"Cluster profile file must contain a JSON object: {profile_file}")
    return data


def parse_cluster_profile_args(profile_name):
    if not profile_name:
        return []

    profiles = load_cluster_profiles()
    if profile_name not in profiles:
        available = ", ".join(sorted(profiles)) or "none"
        raise RuntimeError(
            f"Unknown SLURM_CLUSTER_PROFILE={profile_name!r}. Available profiles: {available}"
        )

    profile = profiles[profile_name]
    args = profile.get("sbatch_extra_args", [])
    if isinstance(args, str):
        return shlex.split(args)
    if isinstance(args, list) and all(isinstance(arg, str) for arg in args):
        return args
    raise RuntimeError(
        f"Cluster profile {profile_name!r} field 'sbatch_extra_args' must be a string or string list"
    )


ALLOCATE_RUNNER_SCRIPT_PATH = os.getenv(
    "ALLOCATE_RUNNER_SCRIPT_PATH", "allocation_scripts/spur_basic.sh"
)

# Timeout configurations
NETWORK_TIMEOUT = env_int("NETWORK_TIMEOUT", 30)
SLURM_COMMAND_TIMEOUT = env_int("SLURM_COMMAND_TIMEOUT", 60)
THREAD_SLEEP_TIMEOUT = env_int("THREAD_SLEEP_TIMEOUT", 10)

SLURM_BIN_DIR = os.getenv("SLURM_BIN_DIR", "")
SLURM_LOG_DIR = os.getenv("SLURM_LOG_DIR", "logs")
RESOURCE_LABEL_PREFIX = os.getenv("RESOURCE_LABEL_PREFIX", "slurm-runner")
RESOURCE_LABEL_ALIASES = parse_key_value_map("RESOURCE_LABEL_ALIASES")
RESOURCE_LABEL_CAPS = parse_key_value_map("RESOURCE_LABEL_CAPS", int)
INCLUDE_TMPDISK_GRES = env_bool("INCLUDE_TMPDISK_GRES", False)
SLURM_CLUSTER_PROFILE = os.getenv("SLURM_CLUSTER_PROFILE", "").strip()
SBATCH_PROFILE_ARGS = parse_cluster_profile_args(SLURM_CLUSTER_PROFILE)
SBATCH_EXTRA_ARGS = SBATCH_PROFILE_ARGS + shlex.split(os.getenv("SBATCH_EXTRA_ARGS", ""))

REPOS_TO_MONITOR = parse_repos()
