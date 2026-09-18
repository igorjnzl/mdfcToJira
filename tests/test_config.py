from __future__ import annotations

import pytest
from mdc_jira.config import ConfigurationError, Settings


def jira_environment() -> dict[str, str]:
    return {
        "JIRA_BASE_URL": "https://example.atlassian.net",
        "JIRA_USER_EMAIL": "automation@example.com",
        "JIRA_API_TOKEN": "not-a-real-token",
        "JIRA_PROJECT_KEY": "AZ",
        "JIRA_EPIC_KEY": "AZ-123",
    }


def test_task_settings_do_not_require_service_management_ids() -> None:
    settings = Settings.from_env(jira_environment())

    assert settings.jira_project_key == "AZ"
    assert settings.jira_epic_key == "AZ-123"
    assert settings.due_days_for("High") == 7


def test_epic_key_is_trimmed() -> None:
    values = jira_environment()
    values["JIRA_EPIC_KEY"] = " AZ-123 "

    assert Settings.from_env(values).jira_epic_key == "AZ-123"


@pytest.mark.parametrize("setting", list(jira_environment()))
def test_missing_jira_setting_is_rejected(setting: str) -> None:
    values = jira_environment()
    del values[setting]

    with pytest.raises(ConfigurationError, match=setting):
        Settings.from_env(values)


@pytest.mark.parametrize("epic_key", ["", " ", "AZ", "123", "AZ-0", "AZ-x", "AZ-123/child"])
def test_missing_or_malformed_epic_key_is_rejected(epic_key: str) -> None:
    values = jira_environment()
    values["JIRA_EPIC_KEY"] = epic_key

    with pytest.raises(ConfigurationError, match="JIRA_EPIC_KEY"):
        Settings.from_env(values)
