from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass


class ConfigurationError(RuntimeError):
    """Raised when required Function App settings are missing or invalid."""


def _required(values: Mapping[str, str], name: str) -> str:
    value = values.get(name, "").strip()
    if not value:
        raise ConfigurationError(f"Required app setting {name} is not configured")
    return value


def _positive_int(values: Mapping[str, str], name: str, default: int) -> int:
    raw_value = values.get(name, str(default)).strip()
    try:
        value = int(raw_value)
    except ValueError as exc:
        raise ConfigurationError(f"App setting {name} must be an integer") from exc
    if value < 1:
        raise ConfigurationError(f"App setting {name} must be greater than zero")
    return value


def _boolean(values: Mapping[str, str], name: str, default: bool) -> bool:
    raw_value = values.get(name, str(default)).strip().casefold()
    if raw_value in {"1", "true", "yes", "on"}:
        return True
    if raw_value in {"0", "false", "no", "off"}:
        return False
    raise ConfigurationError(f"App setting {name} must be true or false")


@dataclass(frozen=True)
class Settings:
    jira_base_url: str
    jira_user_email: str
    jira_api_token: str
    jira_project_key: str
    jira_service_desk_id: str
    jira_request_type_id: str
    high_due_days: int
    medium_due_days: int
    low_due_days: int
    default_due_days: int
    apply_grace_period: bool

    @classmethod
    def from_env(cls, environ: Mapping[str, str] | None = None) -> Settings:
        values = environ if environ is not None else os.environ
        return cls(
            jira_base_url=_required(values, "JIRA_BASE_URL").rstrip("/"),
            jira_user_email=_required(values, "JIRA_USER_EMAIL"),
            jira_api_token=_required(values, "JIRA_API_TOKEN"),
            jira_project_key=_required(values, "JIRA_PROJECT_KEY"),
            jira_service_desk_id=_required(values, "JIRA_SERVICE_DESK_ID"),
            jira_request_type_id=_required(values, "JIRA_REQUEST_TYPE_ID"),
            high_due_days=_positive_int(values, "DEFENDER_HIGH_DUE_DAYS", 7),
            medium_due_days=_positive_int(values, "DEFENDER_MEDIUM_DUE_DAYS", 30),
            low_due_days=_positive_int(values, "DEFENDER_LOW_DUE_DAYS", 90),
            default_due_days=_positive_int(values, "DEFENDER_DEFAULT_DUE_DAYS", 30),
            apply_grace_period=_boolean(values, "DEFENDER_APPLY_GRACE_PERIOD", False),
        )

    def due_days_for(self, severity: str) -> int:
        return {
            "high": self.high_due_days,
            "medium": self.medium_due_days,
            "low": self.low_due_days,
        }.get(severity.casefold(), self.default_due_days)
