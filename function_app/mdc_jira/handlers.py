from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from mdc_jira.config import Settings
from mdc_jira.defender_client import DefenderClient
from mdc_jira.jira_client import JiraClient
from mdc_jira.models import DefenderRecommendation, JiraRequest


def create_jira_task(
    payload: Mapping[str, Any],
    settings: Settings,
    *,
    jira_client: JiraClient | None = None,
) -> JiraRequest:
    recommendation_payload = payload.get("recommendation", payload)
    if not isinstance(recommendation_payload, Mapping):
        raise ValueError("recommendation must be a JSON object")
    recommendation = DefenderRecommendation.from_payload(recommendation_payload)
    client = jira_client or JiraClient(
        base_url=settings.jira_base_url,
        user_email=settings.jira_user_email,
        api_token=settings.jira_api_token,
        project_key=settings.jira_project_key,
        epic_key=settings.jira_epic_key,
    )
    return client.create_or_get(recommendation)


def update_defender_recommendation(
    payload: Mapping[str, Any],
    settings: Settings,
    *,
    defender_client: DefenderClient | None = None,
) -> dict[str, object]:
    recommendation_payload = payload.get("recommendation")
    jira_payload = payload.get("jira")
    if not isinstance(recommendation_payload, Mapping):
        raise ValueError("recommendation must be a JSON object")
    if not isinstance(jira_payload, Mapping):
        raise ValueError("jira must be a JSON object")

    recommendation = DefenderRecommendation.from_payload(recommendation_payload)
    jira_request = JiraRequest(
        issue_id=str(jira_payload.get("issueId", "")).strip(),
        issue_key=str(jira_payload.get("issueKey", "")).strip(),
        web_url=str(jira_payload.get("webUrl", "")).strip(),
        created=bool(jira_payload.get("created", False)),
        correlation_id=str(
            jira_payload.get("correlationId", recommendation.correlation_id)
        ).strip(),
    )
    if not jira_request.issue_id or not jira_request.issue_key or not jira_request.web_url:
        raise ValueError("jira must include issueId, issueKey, and webUrl")
    if jira_request.correlation_id != recommendation.correlation_id:
        raise ValueError("Jira response correlationId does not match the recommendation")

    client = defender_client or DefenderClient(
        apply_grace_period=settings.apply_grace_period,
    )
    return client.assign_jira_request(
        recommendation,
        jira_request,
        due_days=settings.due_days_for(recommendation.severity),
    )
