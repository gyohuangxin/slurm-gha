import os
import shlex

from dotenv import load_dotenv


load_dotenv()


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
INCLUDE_TMPDISK_GRES = env_bool("INCLUDE_TMPDISK_GRES", False)
SBATCH_EXTRA_ARGS = shlex.split(os.getenv("SBATCH_EXTRA_ARGS", ""))

REPOS_TO_MONITOR = parse_repos()
