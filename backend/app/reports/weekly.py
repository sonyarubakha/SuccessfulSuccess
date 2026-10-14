"""Weekly meetings report generation.

This module knows about the database, but nothing about AWS. The same function
can be called locally, from a Lambda handler, or from tests.
"""

import asyncio
import csv
import io
import re
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.config import settings
from app.db import SessionFactory, engine
from app.models import Meeting
from app.models.user import User

_WEEK_RE = re.compile(r"^(?P<year>\d{4})-W(?P<week>\d{2})$")


def _parse_week(week: str) -> date:
    """Return the Monday of an ISO week such as 2026-W40."""
    match = _WEEK_RE.fullmatch(week)

    if not match:
        raise ValueError("week must have the form YYYY-Www, for example 2026-W40")

    year = int(match.group("year"))
    week_number = int(match.group("week"))

    try:
        return date.fromisocalendar(year, week_number, 1)
    except ValueError as exc:
        raise ValueError(f"invalid ISO week: {week}") from exc


def _week_label(day: date) -> str:
    iso = day.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _week_bounds(monday: date) -> tuple[datetime, datetime]:
    start = datetime.combine(monday, time.min, tzinfo=settings.tz)
    return start, start + timedelta(days=7)


async def _meetings_for_week(monday: date) -> list[Meeting]:
    start, end = _week_bounds(monday)

    async with SessionFactory() as session:
        result = await session.scalars(
            select(Meeting)
            .options(selectinload(Meeting.participants))
            .where(
                Meeting.starts_at >= start,
                Meeting.starts_at < end,
            )
            .order_by(Meeting.starts_at.asc(), Meeting.name.asc())
        )
        return list(result)


async def _users_by_id(meetings: list[Meeting]) -> dict[str, User]:
    owner_ids = {meeting.owner_id for meeting in meetings if meeting.owner_id}

    if not owner_ids:
        return {}

    async with SessionFactory() as session:
        result = await session.scalars(select(User).where(User.id.in_(owner_ids)))
        return {user.id: user for user in result}


def _duration_hours(meeting: Meeting) -> float:
    return (meeting.ends_at - meeting.starts_at).total_seconds() / 3600


def _owner_label(owner_id: str | None, users: dict[str, User]) -> str:
    if owner_id is None:
        return "unassigned"

    user = users.get(owner_id)
    if user is None:
        return owner_id

    return user.email or user.name or owner_id


def _owner_totals(meetings: list[Meeting]) -> dict[str | None, tuple[int, float]]:
    totals: dict[str | None, tuple[int, float]] = {}

    for meeting in meetings:
        count, hours = totals.get(meeting.owner_id, (0, 0.0))
        totals[meeting.owner_id] = (
            count + 1,
            hours + _duration_hours(meeting),
        )

    return totals


async def _build_weekly_report(week: str) -> bytes:
    current_monday = _parse_week(week)
    previous_monday = current_monday - timedelta(days=7)
    previous_week = _week_label(previous_monday)

    current = await _meetings_for_week(current_monday)
    previous = await _meetings_for_week(previous_monday)

    users = await _users_by_id(current + previous)

    current_hours = sum(_duration_hours(meeting) for meeting in current)
    previous_hours = sum(_duration_hours(meeting) for meeting in previous)

    current_by_owner = _owner_totals(current)
    previous_by_owner = _owner_totals(previous)

    longest = sorted(
        current,
        key=lambda meeting: (
            -_duration_hours(meeting),
            meeting.starts_at,
            meeting.name,
        ),
    )[:5]

    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")

    writer.writerow(
        [
            "section",
            "week",
            "person",
            "metric",
            "value",
            "change_from_previous",
            "title",
            "start",
            "duration_hours",
            "participants",
        ]
    )

    writer.writerow(
        [
            "summary",
            week,
            "",
            "meeting_count",
            len(current),
            len(current) - len(previous),
            "",
            "",
            "",
            "",
        ]
    )

    writer.writerow(
        [
            "summary",
            week,
            "",
            "total_duration_hours",
            f"{current_hours:.2f}",
            f"{current_hours - previous_hours:.2f}",
            "",
            "",
            "",
            "",
        ]
    )

    writer.writerow(
        [
            "summary",
            previous_week,
            "",
            "meeting_count",
            len(previous),
            "",
            "",
            "",
            "",
            "",
        ]
    )

    writer.writerow(
        [
            "summary",
            previous_week,
            "",
            "total_duration_hours",
            f"{previous_hours:.2f}",
            "",
            "",
            "",
            "",
            "",
        ]
    )

    owner_ids = set(current_by_owner) | set(previous_by_owner)

    for owner_id in sorted(
        owner_ids,
        key=lambda value: _owner_label(value, users).casefold(),
    ):
        current_count, current_owner_hours = current_by_owner.get(owner_id, (0, 0.0))
        previous_count, previous_owner_hours = previous_by_owner.get(owner_id, (0, 0.0))
        person = _owner_label(owner_id, users)

        writer.writerow(
            [
                "person",
                week,
                person,
                "meeting_count",
                current_count,
                current_count - previous_count,
                "",
                "",
                "",
                "",
            ]
        )

        writer.writerow(
            [
                "person",
                week,
                person,
                "total_duration_hours",
                f"{current_owner_hours:.2f}",
                f"{current_owner_hours - previous_owner_hours:.2f}",
                "",
                "",
                "",
                "",
            ]
        )

    for meeting in longest:
        writer.writerow(
            [
                "longest",
                week,
                _owner_label(meeting.owner_id, users),
                "",
                "",
                "",
                meeting.name,
                meeting.starts_at.astimezone(settings.tz).isoformat(),
                f"{_duration_hours(meeting):.2f}",
                len(meeting.participants),
            ]
        )

    return output.getvalue().encode("utf-8")


def build_weekly_report(week: str) -> bytes:
    """Query one ISO week and return its deterministic CSV representation."""

    async def run() -> bytes:
        try:
            return await _build_weekly_report(week)
        finally:
            # asyncio.run() closes its event loop after every invocation.
            # Dispose pooled asyncpg connections first so a warm Lambda
            # invocation never reuses a connection bound to the old loop.
            await engine.dispose()

    return asyncio.run(run())
