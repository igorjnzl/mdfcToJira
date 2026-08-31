from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import requests
from mdc_jira.jira_client import JiraClient
from mdc_jira.models import DefenderRecommendation


class StubResponse:
    def __init__(self, status_code: int, body: Mapping[str, Any]) -> None:
        self.status_code = status_code
        self._body = dict(body)
        self.text = ""

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


def client(session: requests.Session) -> JiraClient:
    return JiraClient(
        base_url="https://example.atlassian.net",
        user_email="automation@example.com",
        api_token="not-a-real-token",
        project_key="SEC",
        service_desk_id="10",
        request_type_id="25",
        session=session,
    )


def test_create_or_get_returns_existing_request() -> None:
    session = StubSession(
        [StubResponse(200, {"issues": [{"id": "10001", "key": "SEC-42"}]})]
    )

    result = client(session).create_or_get(recommendation())

    assert result.issue_key == "SEC-42"
    assert result.created is False
    assert len(session.calls) == 1
    assert session.calls[0][1].endswith("/rest/api/3/search/jql")
    assert recommendation().correlation_marker in session.calls[0][2]["json"]["jql"]


def test_create_or_get_creates_service_request_when_not_found() -> None:
    session = StubSession(
        [
            StubResponse(200, {"issues": []}),
            StubResponse(
                201,
                {
                    "issueId": "10002",
                    "issueKey": "SEC-43",
                    "_links": {"web": "https://example.atlassian.net/portal/SEC-43"},
                },
            ),
        ]
    )

    result = client(session).create_or_get(recommendation())

    assert result.issue_key == "SEC-43"
    assert result.created is True
    create_call = session.calls[1]
    assert create_call[1].endswith("/rest/servicedeskapi/request")
    assert create_call[2]["json"]["serviceDeskId"] == "10"
    assert create_call[2]["json"]["requestTypeId"] == "25"
    fields = create_call[2]["json"]["requestFieldValues"]
    assert recommendation().correlation_marker in fields["summary"]
    assert recommendation().resource_id in fields["description"]