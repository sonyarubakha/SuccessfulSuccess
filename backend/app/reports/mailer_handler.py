"""AWS Lambda entry point for emailing generated weekly reports."""

import logging
import os
from email.message import EmailMessage
from typing import Any
from urllib.parse import unquote_plus

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

s3 = boto3.client("s3")
ses = boto3.client("ses")


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} environment variable is required")
    return value


def _recipients() -> list[str]:
    raw = _required_env("REPORT_RECIPIENTS")
    recipients = [item.strip() for item in raw.split(",") if item.strip()]

    if not recipients:
        raise RuntimeError("REPORT_RECIPIENTS must contain at least one email address")

    return recipients


def _send_report(bucket: str, key: str) -> dict[str, str]:
    sender = _required_env("REPORT_SENDER")
    recipients = _recipients()

    logger.info(
        "report-mailer trigger=s3 bucket=%s key=%s",
        bucket,
        key,
    )

    response = s3.get_object(Bucket=bucket, Key=key)
    report = response["Body"].read()

    filename = key.rsplit("/", 1)[-1]
    week = filename.removesuffix(".csv")

    message = EmailMessage()
    message["Subject"] = f"Weekly meetings report — {week}"
    message["From"] = sender
    message["To"] = ", ".join(recipients)
    message.set_content(f"Attached is the weekly meetings report for {week}.\n")
    message.add_attachment(
        report,
        maintype="text",
        subtype="csv",
        filename=filename,
    )

    result = ses.send_raw_email(
        Source=sender,
        Destinations=recipients,
        RawMessage={"Data": message.as_bytes()},
    )

    message_id = result["MessageId"]

    logger.info(
        "report-mailer sent week=%s message_id=%s",
        week,
        message_id,
    )

    return {
        "week": week,
        "bucket": bucket,
        "key": key,
        "message_id": message_id,
    }


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Send every S3-created CSV report attached to an email."""
    del context

    records = event.get("Records")
    if not records:
        raise ValueError("S3 event contains no Records")

    results = []

    for record in records:
        if record.get("eventSource") != "aws:s3":
            raise ValueError(f"unsupported event source: {record.get('eventSource')}")

        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])

        if not key.startswith("reports/") or not key.endswith(".csv"):
            raise ValueError(f"unexpected report key: {key}")

        results.append(_send_report(bucket, key))

    return {
        "status": "ok",
        "emails": results,
    }
