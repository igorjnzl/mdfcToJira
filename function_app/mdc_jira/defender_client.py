from __future__ import annotations

import re
import uuid
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING, Any, Protocol

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from mdc_jira.models import DefenderRecommendation, JiraRequest

if TYPE_CHECKING:
    from azure.core.credentials import AccessToken

_ARM_SCOPE = "https://management.azure.com/.default"
_API_VERSION = "2022-01-01-preview"
_ASSIGNMENT_NAMESPACE = uuid.UUID("efdd2c1d-abf8-42de-93fc-eebec3f70f87")


class TokenCredential(Protocol):
    def get_token(self, *scopes: str, **kwargs: Any) -> AccessToken: ...


class DefenderApiError(RuntimeError):
    """Raised when Defender for Cloud rejects a governance assignment."""

    def __init__(self, message: str, *, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


class DefenderClient:
    def __init__(
        self,
        *,
        owner_domain: str,
        apply_grace_period: bool,
        timeout_seconds: float = 30.0,
        credential: TokenCredential | None = None,
        session: requests.Session | None = None,
        now: datetime | None = None,
    ) -> None:
        self._owner_domain = owner_domain
        self._apply_grace_period = apply_grace_period
        self._timeout_seconds = timeout_seconds
        self._credential = credential or self._default_credential()
        self._session = session or self._build_session()
        self._now = now

    @staticmethod
    def _default_credential() -> TokenCredential:
        from azure.identity import DefaultAzureCredential

        return DefaultAzureCredential()

    @staticmethod
    def _build_session() -> requests.Session:
        session = requests.Session()
        retry = Retry(
            total=3,
            backoff_factor=0.5,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods=frozenset({"PUT"}),
            respect_retry_after_header=True,
        )
        session.mount("https://", HTTPAdapter(max_retries=retry))
        return session

    def assign_jira_request(
        self,
        recommendation: DefenderRecommendation,
        jira_request: JiraRequest,
        *,
        due_days: int,
    ) -> dict[str, object]:
        assignment_key = str(
            uuid.uuid5(_ASSIGNMENT_NAMESPACE, recommendation.correlation_id)
        )
        owner = self._owner_for(jira_request.issue_key)
        due_date = (self._now or datetime.now(UTC)) + timedelta(days=due_days)
        endpoint = (
            "https://management.azure.com"
            f"{recommendation.assessment_resource_id}/governanceAssignments/{assignment_key}"
            f"?api-version={_API_VERSION}"
        )
        body = {
            "properties": {
                "additionalData": {
                    "ticketLink": jira_request.web_url,
                    "ticketNumber": self._numeric_issue_id(jira_request.issue_id),
                    "ticketStatus": "Active",
                },
                "governanceEmailNotification": {
                    "disableManagerEmailNotification": True,
                    "disableOwnerEmailNotification": True,
                },
                "isGracePeriod": self._apply_grace_period,
                "owner": owner,
                "remediationDueDate": due_date.isoformat(timespec="seconds").replace(
                    "+00:00", "Z"
                ),
            }
        }
        try:
            token = self._credential.get_token(_ARM_SCOPE).token
            response = self._session.put(
                endpoint,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                },
                json=body,
                timeout=self._timeout_seconds,
            )
        except requests.RequestException as exc:
            raise DefenderApiError(
                f"Defender governance request failed: {exc.__class__.__name__}"
            ) from exc
        except Exception as exc:
            raise DefenderApiError(
                f"Could not acquire an Azure management token: {exc.__class__.__name__}",
                status_code=500,
            ) from exc

        if response.status_code not in {200, 201}:
            detail = response.text[:500].strip()
            status_code = 409 if response.status_code == 409 else 502
            raise DefenderApiError(
                f"Defender returned HTTP {response.status_code}: {detail or 'no response body'}",
                status_code=status_code,
            )

        return {
            "success": True,
            "assignmentKey": assignment_key,
            "assignmentId": self._response_id(response),
            "owner": owner,
            "remediationDueDate": body["properties"]["remediationDueDate"],
            "ticketNumber": jira_request.issue_id,
            "ticketLink": jira_request.web_url,
        }

    def _owner_for(self, issue_key: str) -> str:
        local_part = re.sub(r"[^a-z0-9._-]", "-", issue_key.casefold()).strip("-.")
        domain = self._owner_domain.casefold().strip().strip("@")
        if not local_part or not domain:
            raise DefenderApiError("Cannot build the Defender governance owner", status_code=500)
        return f"jira-{local_part}@{domain}"

    @staticmethod
    def _numeric_issue_id(issue_id: str) -> int:
        try:
            value = int(issue_id)
        except ValueError as exc:
            raise DefenderApiError(
                "Jira issueId must be numeric for Defender ticketNumber", status_code=400
            ) from exc
        if value < 0 or value > 2_147_483_647:
            raise DefenderApiError(
                "Jira issueId is outside Defender ticketNumber range", status_code=400
            )
        return value

    @staticmethod
    def _response_id(response: requests.Response) -> str:
        try:
            value = response.json()
        except requests.JSONDecodeError:
            return ""
        return str(value.get("id", "")) if isinstance(value, dict) else ""
