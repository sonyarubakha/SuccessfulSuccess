"""Public Lambda Function URL for authenticated AI agenda parsing."""

import asyncio
import base64
import binascii
import json
import logging
import os
import time
from datetime import date
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from botocore.exceptions import (
    ClientError,
    ConnectTimeoutError,
    EndpointConnectionError,
    ReadTimeoutError,
)

from app.ai.agenda import PROMPT_VERSION, AgendaParseError, parse_agenda
from app.auth import AuthError, AuthNotConfiguredError, get_verifier
from app.config import settings

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

MAX_TEXT_LENGTH = 10_000


def response(status: int, payload: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload, ensure_ascii=False),
    }


def error_response(status: int, code: str, message: str) -> dict:
    return response(
        status,
        {"error": {"code": code, "message": message}},
    )


def cost_usd(usage: dict[str, int]) -> float:
    """Estimate inference cost from configured USD-per-million-token rates."""
    input_rate = float(os.getenv("PARSER_INPUT_PRICE", "0.80"))
    output_rate = float(os.getenv("PARSER_OUTPUT_PRICE", "3.20"))

    total = (usage["input_tokens"] * input_rate + usage["output_tokens"] * output_rate) / 1_000_000

    return round(total, 8)


def read_body(event: dict) -> dict:
    raw = event.get("body") or ""

    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw, validate=True).decode("utf-8")

    payload = json.loads(raw)

    if not isinstance(payload, dict):
        raise ValueError("Request body must be a JSON object")

    return payload


def validate_request(payload: dict) -> tuple[str, date, str]:
    text = payload.get("text")
    today = payload.get("today")
    tz = payload.get("tz")

    if not isinstance(text, str) or not text.strip():
        raise ValueError("text must be a non-empty string")

    if len(text) > MAX_TEXT_LENGTH:
        raise OverflowError("Text exceeds 10,000 characters")

    if not isinstance(today, str):
        raise ValueError("today must be an ISO date")

    if not isinstance(tz, str) or not tz:
        raise ValueError("tz must be an IANA timezone")

    parsed_date = date.fromisoformat(today)
    ZoneInfo(tz)

    return text, parsed_date, tz


def handler(event: dict, context: object) -> dict:
    """Authenticate, parse without database access, return suggestions."""
    method = event.get("requestContext", {}).get("http", {}).get("method", "POST")

    if method != "POST":
        return error_response(405, "method_not_allowed", "Use POST.")

    headers = {key.lower(): value for key, value in (event.get("headers") or {}).items()}

    authorization = headers.get("authorization", "")
    parts = authorization.split()

    if len(parts) != 2 or parts[0].lower() != "bearer":
        return error_response(401, "unauthorized", "Sign in to continue.")

    try:
        user = asyncio.run(get_verifier().verify(parts[1]))
    except AuthError:
        return error_response(401, "unauthorized", "Invalid or expired access token.")
    except AuthNotConfiguredError:
        logger.error("Cognito authentication is not configured")
        return error_response(503, "auth_unavailable", "Authentication is unavailable.")
    except Exception:
        logger.exception("Cognito token verification failed")
        return error_response(503, "auth_unavailable", "Authentication is unavailable.")

    try:
        payload = read_body(event)
        text, today, tz = validate_request(payload)
    except OverflowError:
        return error_response(413, "text_too_long", "Maximum length is 10,000 characters.")
    except (
        ValueError,
        TypeError,
        UnicodeDecodeError,
        binascii.Error,
        ZoneInfoNotFoundError,
    ):
        return error_response(
            400,
            "invalid_request",
            "Provide valid text, today and timezone fields.",
        )

    started = time.monotonic()

    try:
        agenda, usage = parse_agenda(text, today, tz)

    except AgendaParseError as exc:
        return error_response(422, "parse_failed", str(exc))

    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")

        if code in {
            "ThrottlingException",
            "TooManyRequestsException",
            "ServiceQuotaExceededException",
        }:
            return error_response(
                429,
                "service_busy",
                "The AI service is busy. Please try again.",
            )

        logger.error("Bedrock request failed: %s", code)

        return error_response(
            503,
            "ai_unavailable",
            "The AI service is temporarily unavailable.",
        )

    except (
        EndpointConnectionError,
        ConnectTimeoutError,
        ReadTimeoutError,
    ):
        logger.exception("Bedrock connection failed")

        return error_response(
            503,
            "ai_unavailable",
            "The AI service is temporarily unavailable.",
        )

    except Exception:
        logger.exception("Unexpected agenda parsing error")

        return error_response(
            500,
            "internal_error",
            "Could not process the agenda.",
        )

    latency_ms = int((time.monotonic() - started) * 1000)
    price = cost_usd(usage)

    logger.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user.sub,
                "model": settings.parser_model,
                "prompt_version": PROMPT_VERSION,
                "input_tokens": usage["input_tokens"],
                "output_tokens": usage["output_tokens"],
                "latency_ms": latency_ms,
                "cost_usd": price,
            }
        )
    )

    return response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": settings.parser_model,
            "prompt_version": PROMPT_VERSION,
            "usage": usage,
            "latency_ms": latency_ms,
            "cost_usd": price,
        },
    )
