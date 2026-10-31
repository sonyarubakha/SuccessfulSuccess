"""Report request endpoints."""

import json
import os
from datetime import datetime

import boto3
from fastapi import APIRouter, HTTPException, status

from app.auth import CurrentUserDep
from app.config import settings

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post(
    "/current",
    status_code=status.HTTP_202_ACCEPTED,
    summary="Queue this week's report",
)
def request_current_report(user: CurrentUserDep) -> dict[str, str]:
    queue_url = os.getenv("REPORT_QUEUE_URL")
    if not queue_url:
        raise HTTPException(
            status_code=500,
            detail="REPORT_QUEUE_URL is not configured",
        )

    now = datetime.now(settings.tz)
    iso_year, iso_week, _ = now.isocalendar()
    week = f"{iso_year}-W{iso_week:02d}"

    sqs = boto3.client("sqs", region_name=os.getenv("AWS_REGION", "us-east-1"))
    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(
            {
                "week": week,
                "source": "app",
            }
        ),
    )

    return {
        "status": "queued",
        "week": week,
    }
