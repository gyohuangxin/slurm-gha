import os
import threading
import time
from datetime import datetime, timezone

import requests


class GitHubAuth:
    def __init__(
        self,
        access_token=None,
        app_id=None,
        installation_id=None,
        private_key=None,
        timeout=30,
    ):
        self.access_token = access_token
        self.app_id = app_id
        self.installation_id = installation_id
        self.private_key = private_key
        self.timeout = timeout
        self._installation_token = None
        self._installation_token_expires_at = 0
        self._lock = threading.Lock()

    @classmethod
    def from_env(cls):
        access_token = (os.getenv("GITHUB_ACCESS_TOKEN") or "").strip()
        timeout = int(os.getenv("NETWORK_TIMEOUT", "30"))
        if access_token:
            return cls(access_token=access_token, timeout=timeout)

        app_id = (os.getenv("GITHUB_APP_ID") or "").strip()
        installation_id = (os.getenv("GITHUB_APP_INSTALLATION_ID") or "").strip()
        private_key = _read_private_key()

        if app_id and installation_id and private_key:
            return cls(
                app_id=app_id,
                installation_id=installation_id,
                private_key=private_key,
                timeout=timeout,
            )

        raise RuntimeError(
            "Configure either GITHUB_ACCESS_TOKEN or GitHub App credentials: "
            "GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, and "
            "GITHUB_APP_PRIVATE_KEY_PATH or GITHUB_APP_PRIVATE_KEY."
        )

    def headers(self):
        return {
            "Authorization": f"Bearer {self.token()}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    def token(self):
        if self.access_token:
            return self.access_token

        with self._lock:
            now = int(time.time())
            if (
                self._installation_token
                and self._installation_token_expires_at - now > 300
            ):
                return self._installation_token

            token, expires_at = self._create_installation_token()
            self._installation_token = token
            self._installation_token_expires_at = expires_at
            return token

    def _create_installation_token(self):
        endpoint = (
            "https://api.github.com/app/installations/"
            f"{self.installation_id}/access_tokens"
        )
        response = requests.post(
            endpoint,
            headers={
                "Authorization": f"Bearer {self._create_app_jwt()}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json()
        expires_at = _parse_github_timestamp(payload["expires_at"])
        return payload["token"], expires_at

    def _create_app_jwt(self):
        try:
            import jwt
        except ImportError as exc:
            raise RuntimeError(
                "GitHub App authentication requires PyJWT with crypto support. "
                "Run: python3 -m pip install -r requirements.txt"
            ) from exc

        now = int(time.time())
        return jwt.encode(
            {
                "iat": now - 60,
                "exp": now + 9 * 60,
                "iss": self.app_id,
            },
            self.private_key,
            algorithm="RS256",
        )


def _read_private_key():
    key = os.getenv("GITHUB_APP_PRIVATE_KEY")
    if key:
        return key.replace("\\n", "\n")

    path = os.getenv("GITHUB_APP_PRIVATE_KEY_PATH")
    if path:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()

    return ""


def _parse_github_timestamp(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return int(parsed.astimezone(timezone.utc).timestamp())
