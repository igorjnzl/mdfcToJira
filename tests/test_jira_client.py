from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import replace
from typing import Any

import pytest
import requests
from mdc_jira.jira_client import JiraApiError, JiraClient
from mdc_jira.models import DefenderRecommendation


class StubResponse:
    def __init__(self, status_code: int, body: Mapping[str, Any]) -> None:
        self.status_code = status_code
        self._body = dict(body)
        self.text = json.dumps(body)

    def json(self) -> dict[str, Any]:
        return self._body


class StubSession(requests.Session):
    def __init__(self, responses: list[StubResponse]) -> None:
        super().__init__()
        self._responses = responses
        self.calls: list[tuple[str, str, dict[str, Any]]] = []

    def request(self, method: str, url: str, **kwargs: Any) -> StubResponse:
        self.calls.append((method, url, kwargs))
        return self._responses.pop(0)


def recommendation() -> DefenderRecommendation:
    return DefenderRecommendation.from_payload(
        {
            "id": (
                "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app/"
                "providers/Microsoft.Compute/virtualMachines/vm-01/providers/"
                "Microsoft.Security/assessments/assessment-guid"
            ),
            "name": "assessment-guid",
            "properties": {
                "displayName": "Machines should have a vulnerability assessment solution",
                "resourceDetails": {
                    "Id": (
                        "/subscriptions/00000000-0000-0000-0000-000000000000/"
                        "resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-01"
                    )
                },
                "status": {"code": "Unhealthy"},
                "metadata": {
                    "severity": "High",
                    "description": "A vulnerability assessment solution is missing.",
                    "remediationDescription": "Install a supported vulnerability scanner.",
                },
            },
        }
    )


def client(session: requests.Session, *, epic_key: str = "SEC-1") -> JiraClient:
    return JiraClient(
        base_url="https://example.atlassian.net",
        user_email="automation@example.com",
        api_token="not-a-real-token",
        project_key="SEC",
        epic_key=epic_key,
        session=session,
    )


def test_create_or_get_returns_existing_ticket_without_reparenting() -> None:
    session = StubSession(
        [StubResponse(200, {"issues": [{"id": "10001", "key": "SEC-42"}]})]
    )

    result = client(session).create_or_get(recommendation())

    assert result.issue_key == "SEC-42"
    assert result.web_url == "https://example.atlassian.net/browse/SEC-42"
    assert result.created is False
    assert len(session.calls) == 1
    assert session.calls[0][1].endswith("/rest/api/3/search/jql")
    jql = session.calls[0][2]["json"]["jql"]
    assert recommendation().correlation_marker in jql
    assert 'project = "SEC"' in jql
    assert "parent" not in jql


@pytest.mark.parametrize("epic_key", ["SEC-1", "SEC-99"])
def test_create_or_get_creates_task_under_configured_epic(epic_key: str) -> None:
    session = StubSession(
        [
            StubResponse(200, {"issues": []}),
            StubResponse(
                201,
                {
                    "id": "10002",
                    "key": "SEC-43",
                    "self": "https://example.atlassian.net/rest/api/3/issue/10002",
                },
            ),
        ]
    )

    result = client(session, epic_key=epic_key).create_or_get(recommendation())

    assert result.issue_id == "10002"
    assert result.issue_key == "SEC-43"
    assert result.web_url == "https://example.atlassian.net/browse/SEC-43"
    assert result.correlation_id == recommendation().correlation_id
    assert result.created is True
    assert len(session.calls) == 2
    create_call = session.calls[1]
    assert create_call[0] == "POST"
    assert create_call[1] == "https://example.atlassian.net/rest/api/3/issue"
    assert set(create_call[2]["json"]) == {"fields"}
    fields = create_call[2]["json"]["fields"]
    assert set(fields) == {"project", "issuetype", "parent", "summary", "description"}
    assert fields["project"] == {"key": "SEC"}
    assert fields["issuetype"] == {"name": "Task"}
    assert fields["parent"] == {"key": epic_key}
    assert recommendation().correlation_marker in fields["summary"]
    description = fields["description"]
    assert description["type"] == "doc"
    assert description["version"] == 1
    text = "\n".join(
        node["text"] for paragraph in description["content"] for node in paragraph["content"]
    )
    for value in (
        recommendation().display_name,
        recommendation().resource_id,
        recommendation().severity,
        recommendation().description,
        recommendation().remediation_description,
        recommendation().defender_portal_url,
        recommendation().correlation_id,
    ):
        assert value in text


@pytest.mark.parametrize("description", ["", "First line\r\nSecond line\n\nThird line"])
def test_jira_description_uses_adf_paragraphs_for_multiline_text(description: str) -> None:
    value = replace(recommendation(), description=description)
    document = value.jira_description()
    expected_lines = [
        "Microsoft Defender for Cloud recommendation",
        "",
        f"Recommendation: {value.display_name}",
        f"Severity: {value.severity}",
        f"Status: {value.status}",
        f"Affected resource: {value.resource_id}",
        f"Assessment key: {value.assessment_key}",
        f"Correlation ID: {value.correlation_id}",
        f"Defender portal: {value.defender_portal_url}",
    ]
    if description:
        expected_lines.extend(["", "Description", *description.splitlines()])
    expected_lines.extend(["", "Recommended remediation", value.remediation_description])
    assert document == {
        "type": "doc",
        "version": 1,
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": line}] if line else []}
            for line in expected_lines
        ],
    }


@pytest.mark.parametrize("status_code", [400, 403, 404])
def test_rejected_epic_or_task_creation_surfaces_jira_error(status_code: int) -> None:
    session = StubSession(
        [
            StubResponse(200, {"issues": []}),
            StubResponse(status_code, {"errors": {"parent": "Epic is unavailable"}}),
        ]
    )

    with pytest.raises(JiraApiError, match=f"HTTP {status_code}.*Epic is unavailable"):
        client(session).create_or_get(recommendation())

    assert len(session.calls) == 2


def test_failed_search_does_not_create_a_duplicate_task() -> None:
    session = StubSession([StubResponse(403, {"errorMessages": ["Access denied"]})])

    with pytest.raises(JiraApiError, match="HTTP 403"):
        client(session).create_or_get(recommendation())

    assert len(session.calls) == 1