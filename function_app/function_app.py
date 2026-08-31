from __future__ import annotations

import json
import logging
from collections.abc import Mapping
from typing import Any

import azure.functions as func
from mdc_jira.config import ConfigurationError, Settings
from mdc_jira.defender_client import DefenderApiError
from mdc_jira.handlers import create_jira_service_request, update_defender_recommendation
from mdc_jira.jira_client import JiraApiError
from mdc_jira.models import PayloadValidationError

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
logger = logging.getLogger(__name__)


def _request_json(req: func.HttpRequest) -> Mapping[str, Any]:
    try:
        payload = req.get_json()
    except ValueError as exc:
        raise ValueError("Request body must contain valid JSON") from exc
    if not isinstance(payload, Mapping):
        raise ValueError("Request body must be a JSON object")
    return payload


def _json_response(payload: Mapping[str, object], status_code: int) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(payload),
        status_code=status_code,
        mimetype="application/json",
    )


def _error_response(exc: Exception) -> func.HttpResponse:
    if isinstance(exc, (ValueError, PayloadValidationError)):
        status_code = 400
    elif isinstance(exc, ConfigurationError):
        status_code = 500
    elif isinstance(exc, (JiraApiError, DefenderApiError)):
        status_code = exc.status_code
    else:
        logger.exception("Unhandled integration error")
        status_code = 500
    if status_code >= 500:
        logger.error("Integration request failed: %s", exc)
    return _json_response(
        {"success": False, "error": str(exc), "errorType": exc.__class__.__name__},
        status_code,
    )


@app.route(route="jira/requests", methods=["POST"])
def create_jira_request(req: func.HttpRequest) -> func.HttpResponse:
    try:
        result = create_jira_service_request(_request_json(req), Settings.from_env())
        return _json_response(result.to_dict(), 201 if result.created else 200)
    except Exception as exc:
        return _error_response(exc)


@app.route(route="defender/recommendations/assign", methods=["POST"])
def assign_defender_recommendation(req: func.HttpRequest) -> func.HttpResponse:
    try:
        result = update_defender_recommendation(_request_json(req), Settings.from_env())
        return _json_response(result, 200)
    except Exception as exc:
        return _error_response(exc)
