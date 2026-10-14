"""AWS Lambda entry point for building weekly meeting reports."""

import json
import logging
import os
from datetime import datetime, timedelta
from typing import Any

import boto3

from app.config import settings
from app.reports.weekly import build_weekly_report

logger = logging.getLogger(__name__)
logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

s3 = boto3.client("s3")


def _previous_iso_week() -> str:
    """Return the previous ISO week in the application's timezone."""
    previous_week_day = datetime.now(settings.tz).date() - timedelta(days=7)
    iso = previous_week_day.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _report_bucket() -> str:
    bucket = os.getenv("REPORT_BUCKET")
    if not bucket:
        raise RuntimeError("REPORT_BUCKET environment variable is required")
    return bucket


def _build_and_upload(payload: dict[str, Any], trigger: str) -> dict[str, str]:
    week = payload.get("week") or _previous_iso_week()
    source = payload.get("source") or trigger

    if source == "schedule":
        trigger = "schedule"

    logger.info(
        "report-builder trigger=%s source=%s week=%s",
        trigger,
        source,
        week,
    )

    report = build_weekly_report(week)

    bucket = _report_bucket()
    key = f"reports/{week}.csv"

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=report,
        ContentType="text/csv; charset=utf-8",
    )

    logger.info(
        "report-builder uploaded bucket=%s key=%s",
        bucket,
        key,
    )

    return {
        "week": week,
        "bucket": bucket,
        "key": key,
    }


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Build reports from direct/scheduled invocations or SQS messages."""
    del context

    records = event.get("Records")

    if records:
        results = []

        for record in records:
            if record.get("eventSource") != "aws:sqs":
                raise ValueError(f"unsupported event source: {record.get('eventSource')}")

            payload = json.loads(record["body"])

            if not isinstance(payload, dict):
                raise ValueError("SQS message body must contain a JSON object")

            results.append(_build_and_upload(payload, trigger="sqs"))

        return {
            "status": "ok",
            "reports": results,
        }

    return {
        "status": "ok",
        "reports": [_build_and_upload(event, trigger="direct")],
    }
