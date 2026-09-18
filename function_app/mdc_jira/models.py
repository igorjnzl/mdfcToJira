from __future__ import annotations

import hashlib
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote


class PayloadValidationError(ValueError):
    """Raised when a Defender workflow payload lacks required identifiers."""


def _as_mapping(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _get_case_insensitive(values: Mapping[str, Any], *names: str) -> Any:
    normalized = {str(key).casefold(): value for key, value in values.items()}
    for name in names:
        if name.casefold() in normalized:
            return normalized[name.casefold()]
    return None


def _text(value: object) -> str:
    return str(value).strip() if value is not None else ""


@dataclass(frozen=True)
class DefenderRecommendation:
    assessment_resource_id: str
    assessment_key: str
    resource_id: str
    display_name: str
    description: str
    remediation_description: str
    severity: str
    status: str

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> DefenderRecommendation:
        properties = _as_mapping(_get_case_insensitive(payload, "properties"))
        metadata = _as_mapping(_get_case_insensitive(properties, "metadata"))
        resource_details = _as_mapping(
            _get_case_insensitive(properties, "resourceDetails", "resource_details")
        )
        status = _as_mapping(_get_case_insensitive(properties, "status"))

        assessment_resource_id = _text(
            _get_case_insensitive(payload, "id", "assessmentResourceId", "assessment_id")
        )
        assessment_key = _text(
            _get_case_insensitive(payload, "name", "assessmentKey", "assessment_key")
        )
        if not assessment_key and "/assessments/" in assessment_resource_id.casefold():
            assessment_key = assessment_resource_id.rstrip("/").rsplit("/", 1)[-1]

        resource_id = _text(
            _get_case_insensitive(resource_details, "id", "resourceId", "resource_id")
            or _get_case_insensitive(payload, "resourceId", "resource_id")
        )
        marker = "/providers/microsoft.security/assessments/"
        marker_index = assessment_resource_id.casefold().find(marker)
        if not resource_id and marker_index > 0:
            resource_id = assessment_resource_id[:marker_index]

        if not assessment_resource_id:
            raise PayloadValidationError("Defender payload is missing the assessment resource id")
        if not assessment_key:
            raise PayloadValidationError("Defender payload is missing the assessment key")
        if not resource_id:
            raise PayloadValidationError("Defender payload is missing the affected resource id")

        return cls(
            assessment_resource_id=assessment_resource_id,
            assessment_key=assessment_key,
            resource_id=resource_id,
            display_name=_text(
                _get_case_insensitive(properties, "displayName", "display_name")
                or _get_case_insensitive(metadata, "displayName", "display_name")
                or "Microsoft Defender for Cloud recommendation"
            ),
            description=_text(
                _get_case_insensitive(metadata, "description")
                or _get_case_insensitive(properties, "description")
            ),
            remediation_description=_text(
                _get_case_insensitive(
                    metadata, "remediationDescription", "remediation_description"
                )
                or _get_case_insensitive(
                    properties, "remediationDescription", "remediation_description"
                )
            ),
            severity=_text(_get_case_insensitive(metadata, "severity") or "Unknown"),
            status=_text(_get_case_insensitive(status, "code") or "Unknown"),
        )

    @property
    def correlation_id(self) -> str:
        source = f"{self.assessment_key.casefold()}|{self.resource_id.casefold()}"
        return hashlib.sha256(source.encode("utf-8")).hexdigest()

    @property
    def correlation_marker(self) -> str:
        return f"mdc-{self.correlation_id[:24]}"

    @property
    def resource_name(self) -> str:
        return self.resource_id.rstrip("/").rsplit("/", 1)[-1]

    @property
    def jira_summary(self) -> str:
        prefix = f"[{self.severity}] {self.display_name} - {self.resource_name}"
        suffix = f" [{self.correlation_marker}]"
        return f"{prefix[: 255 - len(suffix)].rstrip()}{suffix}"

    @property
    def defender_portal_url(self) -> str:
        encoded_resource = quote(self.resource_id, safe="")
        encoded_assessment = quote(self.assessment_key, safe="")
        return (
            "https://portal.azure.com/#view/Microsoft_Azure_Security/"
            f"RecommendationDetailsBlade/assessmentKey/{encoded_assessment}/"
            f"resourceId/{encoded_resource}"
        )

    def jira_description(self) -> dict[str, object]:
        lines = [
            "Microsoft Defender for Cloud recommendation",
            "",
            f"Recommendation: {self.display_name}",
            f"Severity: {self.severity}",
            f"Status: {self.status}",
            f"Affected resource: {self.resource_id}",
            f"Assessment key: {self.assessment_key}",
            f"Correlation ID: {self.correlation_id}",
            f"Defender portal: {self.defender_portal_url}",
        ]
        if self.description:
            lines.extend(("", "Description", self.description))
        if self.remediation_description:
            lines.extend(("", "Recommended remediation", self.remediation_description))
        return {
            "type": "doc",
            "version": 1,
            "content": [
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": line}] if line else [],
                }
                for line in "\n".join(lines).splitlines()
            ],
        }


@dataclass(frozen=True)
class JiraRequest:
    issue_id: str
    issue_key: str
    web_url: str
    created: bool
    correlation_id: str

    def to_dict(self) -> dict[str, object]:
        return {
            "success": True,
            "created": self.created,
            "correlationId": self.correlation_id,
            "issueId": self.issue_id,
            "issueKey": self.issue_key,
            "webUrl": self.web_url,
        }
