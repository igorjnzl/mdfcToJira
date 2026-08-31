from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import requests
from mdc_jira.defender_client import DefenderClient
from mdc_jira.models import JiraRequest
from test_jira_client import StubResponse, recommendation


@dataclass(frozen=True)
class StubAccessToken:
    token: str
    expires_on: int


class StubCredential:
    def get_token(self, *scopes: str, **kwargs: Any) -> StubAccessToken:
        assert scopes == ("https://management.azure.com/.default",)
        return StubAccessToken("arm-token", 4_102_444_800)


class PutSession(requests.Session):
    def __init__(self) -> None:
        super().__init__()
        self.call: tuple[str, dict[str, Any]] | None = None

    def put(self, url: str, **kwargs: Any) -> StubResponse:
        self.call = (url, kwargs)
        return StubResponse(201, {"id": "/governanceAssignments/assignment-id"})


def test_assign_jira_request_writes_ticket_details_and_owner() -> None:
    session = PutSession()
    jira_request = JiraRequest(
        issue_id="10002",
        issue_key="SEC-43",
        web_url="https://example.atlassian.net/browse/SEC-43",
        created=True,
        correlation_id=recommendation().correlation_id,
    )
    client = DefenderClient(
        owner_domain="jira.local",
        apply_grace_period=False,
        credential=StubCredential(),
        session=session,
        now=datetime(2026, 8, 28, 12, 0, tzinfo=UTC),
    )

    result = client.assign_jira_request(recommendation(), jira_request, due_days=7)

    assert session.call is not None
    url, request = session.call
    assert recommendation().assessment_resource_id in url
    assert "api-version=2022-01-01-preview" in url
    assert request["headers"]["Authorization"] == "Bearer arm-token"
    properties = request["json"]["properties"]
    assert properties["owner"] == "jira-sec-43@jira.local"
    assert properties["remediationDueDate"] == "2026-09-04T12:00:00Z"
    assert properties["isGracePeriod"] is False
    assert properties["additionalData"] == {
        "ticketLink": "https://example.atlassian.net/browse/SEC-43",
        "ticketNumber": 10002,
        "ticketStatus": "Active",
    }
    assert result["ticketNumber"] == "10002"
