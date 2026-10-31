"""Parser contract tests without AWS or database dependencies."""

from datetime import date
from unittest.mock import Mock, patch

import pytest

from app.ai.agenda import AgendaParseError, parse_agenda
from app.ai.agenda_lambda import handler, validate_request
from app.auth import CurrentUser


def reply(payload):
    return {
        "stopReason": "tool_use",
        "usage": {"inputTokens": 10, "outputTokens": 5},
        "output": {
            "message": {
                "role": "assistant",
                "content": [
                    {"toolUse": {"name": "record_agenda", "toolUseId": "one", "input": payload}}
                ],
            }
        },
    }


def test_retry_and_accumulated_usage():
    client = Mock()
    client.converse.side_effect = [
        reply({"items": [{"topic": "Plan", "minutes": 0}], "language": "en"}),
        reply({"items": [{"topic": "Plan", "minutes": 15}], "language": "en"}),
    ]
    with patch("app.ai.agenda.boto3.client", return_value=client):
        agenda, usage = parse_agenda("Plan, 15 minutes", date(2026, 10, 29), "Europe/Kyiv")
    assert agenda.items[0].minutes == 15
    assert usage == {"input_tokens": 20, "output_tokens": 10}
    assert client.converse.call_count == 2


def test_unrelated_text_is_rejected():
    client = Mock()
    client.converse.return_value = reply({"items": [], "language": "en"})
    with patch("app.ai.agenda.boto3.client", return_value=client):
        with pytest.raises(AgendaParseError, match="No meeting agenda"):
            parse_agenda("milk", date(2026, 10, 29), "Europe/Kyiv")


def test_auth_before_model():
    with patch("app.ai.agenda_lambda.parse_agenda") as parse:
        assert handler({"body": "{}"}, None)["statusCode"] == 401
        parse.assert_not_called()


def test_length_limit():
    with pytest.raises(OverflowError):
        validate_request({"text": "x" * 10001, "today": "2026-10-29", "tz": "Europe/Kyiv"})


def test_invalid_timezone():
    from zoneinfo import ZoneInfoNotFoundError

    with pytest.raises(ZoneInfoNotFoundError):
        validate_request({"text": "Plan", "today": "2026-10-29", "tz": "invalid"})


def test_authenticated_oversize_is_413():
    import json
    from unittest.mock import AsyncMock

    verifier = Mock()
    verifier.verify = AsyncMock(return_value=CurrentUser(sub="test"))
    with patch("app.ai.agenda_lambda.get_verifier", return_value=verifier):
        result = handler(
            {
                "headers": {"Authorization": "Bearer token"},
                "body": json.dumps(
                    {"text": "x" * 10001, "today": "2026-10-29", "tz": "Europe/Kyiv"}
                ),
            },
            None,
        )
    assert result["statusCode"] == 413
