from __future__ import annotations

import json

import azure.functions as func
import pytest
from mdc_jira.jira_client import JiraClient
from test_config import jira_environment
from test_jira_client import StubResponse, StubSession, recommendation

from function_app import create_jira_request


@pytest.mark.parametrize("existing", [False, True])
@pytest.mark.parametrize("wrapped", [False, True])
def test_http_route_preserves_logic_app_contract(
    monkeypatch: pytest.MonkeyPatch, existing: bool, wrapped: bool
) -> None:
    for name, value in jira_environment().items():
        monkeypatch.setenv(name, value)
    issue = {"id": "10002", "key": "AZ-124"}
    session = StubSession(
        [StubResponse(200, {"issues": [issue]})]
        if existing
        else [StubResponse(200, {"issues": []}), StubResponse(201, issue)]
    )
    monkeypatch.setattr(JiraClient, "_build_session", staticmethod(lambda: session))
    payload = {
        "id": recommendation().assessment_resource_id,
        "name": recommendation().assessment_key,
    }
    req = func.HttpRequest(
        method="POST",
        url="https://function.example.com/api/jira/requests",
        body=json.dumps({"recommendation": payload} if wrapped else payload).encode(),
    )

    response = create_jira_request(req)

    assert response.status_code == (200 if existing else 201)
    assert json.loads(response.get_body()) == {
        "success": True,
        "created": not existing,
        "correlationId": recommendation().correlation_id,
        "issueId": "10002",
        "issueKey": "AZ-124",
        "webUrl": "https://example.atlassian.net/browse/AZ-124",
    }
    assert session.auth == ("automation@example.com", "not-a-real-token")
    if not existing:
        fields = session.calls[1][2]["json"]["fields"]
        assert fields["project"] == {"key": "AZ"}
        assert fields["parent"] == {"key": "AZ-123"}
        assert fields["issuetype"] == {"name": "Task"}


def test_http_route_reports_missing_epic_configuration(monkeypatch: pytest.MonkeyPatch) -> None:
    for name, value in jira_environment().items():
        monkeypatch.setenv(name, value)
    monkeypatch.delenv("JIRA_EPIC_KEY")
    req = func.HttpRequest(
        method="POST",
        url="https://function.example.com/api/jira/requests",
        body=b"{}",
    )

    response = create_jira_request(req)

    assert response.status_code == 500
    body = json.loads(response.get_body())
    assert body["success"] is False
    assert body["errorType"] == "ConfigurationError"
    assert "JIRA_EPIC_KEY" in body["error"]
