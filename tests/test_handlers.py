from __future__ import annotations

from typing import Any

from mdc_jira.config import Settings
from mdc_jira.handlers import update_defender_recommendation
from mdc_jira.models import DefenderRecommendation, JiraRequest
from test_jira_client import recommendation


class StubDefenderClient:
    def __init__(self) -> None:
        self.due_days = 0

    def assign_jira_request(
        self,
        recommendation_value: DefenderRecommendation,
        jira_request: JiraRequest,
        *,
        due_days: int,
    ) -> dict[str, object]:
        assert recommendation_value.assessment_key == "assessment-guid"
        assert jira_request.issue_key == "SEC-43"
        self.due_days = due_days
        return {"success": True, "assignmentKey": "assignment-key"}


def settings() -> Settings:
    return Settings.from_env(
        {
            "JIRA_BASE_URL": "https://example.atlassian.net",
            "JIRA_USER_EMAIL": "automation@example.com",
            "JIRA_API_TOKEN": "not-a-real-token",
            "JIRA_PROJECT_KEY": "SEC",
            "JIRA_EPIC_KEY": "SEC-1",
            "DEFENDER_HIGH_DUE_DAYS": "7",
        }
    )


def test_update_defender_recommendation_validates_correlation_and_uses_severity_sla() -> None:
    recommendation_value = recommendation()
    defender_client = StubDefenderClient()
    payload: dict[str, Any] = {
        "recommendation": {
            "id": recommendation_value.assessment_resource_id,
            "name": recommendation_value.assessment_key,
            "properties": {
                "displayName": recommendation_value.display_name,
                "resourceDetails": {"id": recommendation_value.resource_id},
                "metadata": {"severity": "High"},
            },
        },
        "jira": {
            "success": True,
            "created": True,
            "correlationId": recommendation_value.correlation_id,
            "issueId": "10002",
            "issueKey": "SEC-43",
            "webUrl": "https://example.atlassian.net/browse/SEC-43",
        },
    }

    result = update_defender_recommendation(
        payload, settings(), defender_client=defender_client  # type: ignore[arg-type]
    )

    assert result["success"] is True
    assert defender_client.due_days == 7