from __future__ import annotations

from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from mdc_jira.models import DefenderRecommendation, JiraRequest


class JiraApiError(RuntimeError):
    """Raised when Jira rejects a request or returns an invalid response."""

    def __init__(self, message: str, *, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


class JiraClient:
    def __init__(
        self,
        *,
        base_url: str,
        user_email: str,
        api_token: str,
        project_key: str,
        epic_key: str,
        timeout_seconds: float = 30.0,
        session: requests.Session | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._project_key = project_key
        self._epic_key = epic_key
        self._timeout_seconds = timeout_seconds
        self._session = session or self._build_session()
        self._session.auth = (user_email, api_token)
        self._session.headers.update(
            {"Accept": "application/json", "Content-Type": "application/json"}
        )

    @staticmethod
    def _build_session() -> requests.Session:
        session = requests.Session()
        retry = Retry(
            total=3,
            backoff_factor=0.5,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods=frozenset({"GET", "PUT"}),
            respect_retry_after_header=True,
        )
        session.mount("https://", HTTPAdapter(max_retries=retry))
        return session

    def create_or_get(self, recommendation: DefenderRecommendation) -> JiraRequest:
        existing = self._find_existing(recommendation)
        if existing is not None:
            return existing
        return self._create_task(recommendation)

    def _find_existing(self, recommendation: DefenderRecommendation) -> JiraRequest | None:
        marker = recommendation.correlation_marker
        project = self._escape_jql(self._project_key)
        jql_marker = self._escape_jql(marker)
        jql = (
            f'project = "{project}" AND summary ~ "\\\"{jql_marker}\\\"" '
            "ORDER BY created DESC"
        )
        response = self._send(
            "POST",
            "/rest/api/3/search/jql",
            json={"jql": jql, "fields": ["summary"], "maxResults": 1},
        )
        issues = self._json_object(response).get("issues", [])
        if not isinstance(issues, list) or not issues:
            return None
        issue = issues[0]
        if not isinstance(issue, dict):
            raise JiraApiError("Jira search returned an invalid issue object")
        return self._to_result(issue, recommendation.correlation_id, created=False)

    def _create_task(self, recommendation: DefenderRecommendation) -> JiraRequest:
        response = self._send(
            "POST",
            "/rest/api/3/issue",
            expected_status=201,
            json={
                "fields": {
                    "project": {"key": self._project_key},
                    "issuetype": {"name": "Task"},
                    "parent": {"key": self._epic_key},
                    "summary": recommendation.jira_summary,
                    "description": recommendation.jira_description(),
                },
            },
        )
        return self._to_result(
            self._json_object(response), recommendation.correlation_id, created=True
        )

    def _send(
        self,
        method: str,
        path: str,
        *,
        expected_status: int = 200,
        **kwargs: Any,
    ) -> requests.Response:
        try:
            response = self._session.request(
                method,
                f"{self._base_url}{path}",
                timeout=self._timeout_seconds,
                **kwargs,
            )
        except requests.RequestException as exc:
            raise JiraApiError(f"Jira request failed: {exc.__class__.__name__}") from exc
        if response.status_code != expected_status:
            detail = response.text[:500].strip()
            raise JiraApiError(
                f"Jira returned HTTP {response.status_code}: {detail or 'no response body'}",
                status_code=502,
            )
        return response

    @staticmethod
    def _json_object(response: requests.Response) -> dict[str, Any]:
        try:
            value = response.json()
        except requests.JSONDecodeError as exc:
            raise JiraApiError("Jira returned a non-JSON response") from exc
        if not isinstance(value, dict):
            raise JiraApiError("Jira returned an invalid JSON response")
        return value

    def _to_result(
        self, issue: dict[str, Any], correlation_id: str, *, created: bool
    ) -> JiraRequest:
        issue_id = str(issue.get("issueId") or issue.get("id") or "").strip()
        issue_key = str(issue.get("issueKey") or issue.get("key") or "").strip()
        if not issue_id or not issue_key:
            raise JiraApiError("Jira response is missing issueId or issueKey")
        links = issue.get("_links")
        web_url = links.get("web") if isinstance(links, dict) else None
        return JiraRequest(
            issue_id=issue_id,
            issue_key=issue_key,
            web_url=str(web_url or f"{self._base_url}/browse/{issue_key}"),
            created=created,
            correlation_id=correlation_id,
        )

    @staticmethod
    def _escape_jql(value: str) -> str:
        return value.replace("\\", "\\\\").replace('"', '\\"')
