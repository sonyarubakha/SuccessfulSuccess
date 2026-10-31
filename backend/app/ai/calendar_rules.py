"""Deterministic normalization of explicitly stated relative weekdays."""

import re
from datetime import date, datetime, timedelta
from typing import TYPE_CHECKING
from zoneinfo import ZoneInfo

if TYPE_CHECKING:
    from app.ai.agenda import ParsedAgenda


WEEKDAYS = {
    "пн": 0,
    "вт": 1,
    "ср": 2,
    "чт": 3,
    "пт": 4,
    "сб": 5,
    "нд": 6,
    "mon": 0,
    "tue": 1,
    "wed": 2,
    "thu": 3,
    "fri": 4,
    "sat": 5,
    "sun": 6,
}

DUE_WEEKDAYS = {
    "понеділка": 0,
    "вівторка": 1,
    "середи": 2,
    "четверга": 3,
    "п'ятниці": 4,
    "п’ятниці": 4,
    "пʼятниці": 4,
    "суботи": 5,
    "неділі": 6,
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}

START_WEEKDAYS = {
    **WEEKDAYS,
    "понеділок": 0,
    "вівторок": 1,
    "середу": 2,
    "середа": 2,
    "четвер": 3,
    "п'ятницю": 4,
    "п’ятницю": 4,
    "пʼятницю": 4,
    "суботу": 5,
    "неділю": 6,
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}

START_PATTERN = re.compile(
    r"^\s*(?:(?:у|в|на|on)\s+)?"
    r"(?P<weekday>понеділок|вівторок|середу|середа|четвер|п['’ʼ]ятницю|"
    r"суботу|неділю|пн|вт|ср|чт|пт|сб|нд|"
    r"mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|"
    r"thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)"
    r"\.?\s+(?:(?:о|at)\s+)?"
    r"(?P<hour>\d{1,2}):(?P<minute>\d{2})"
    r"(?:\s*[,—:-]?\s*(?P<title>[^,\n.]+))?",
    re.IGNORECASE,
)

DUE_PATTERN = re.compile(
    r"\b(?:до\s+(?P<ua>понеділка|вівторка|середи|четверга|"
    r"п['’ʼ]ятниці|суботи|неділі)|"
    r"by\s+(?P<en>monday|tuesday|wednesday|thursday|"
    r"friday|saturday|sunday))\b",
    re.IGNORECASE,
)


def next_weekday(today: date, weekday: int) -> date:
    """The nearest occurrence of a weekday on or after today."""
    days_ahead = (weekday - today.weekday()) % 7
    return today + timedelta(days=days_ahead)


def normalize_calendar_fields(
    agenda: "ParsedAgenda",
    text: str,
    today: date,
    tz: str,
) -> "ParsedAgenda":
    """Correct deterministic fields that are explicit in the source text."""

    # Vague times do not justify a precise timestamp, even if the model invents one.
    if re.search(r"after lunch|після обіду", text, re.IGNORECASE) and not re.search(
        r"\b\d{1,2}:\d{2}\b", text
    ):
        agenda.starts_at = None

    start = START_PATTERN.match(text)

    if start:
        token = start.group("weekday").lower()
        weekday = START_WEEKDAYS[token]

        hour = int(start.group("hour"))
        minute = int(start.group("minute"))

        if hour <= 23 and minute <= 59:
            day = next_weekday(today, weekday)
            local_start = datetime(
                day.year,
                day.month,
                day.day,
                hour,
                minute,
                tzinfo=ZoneInfo(tz),
            )
            agenda.starts_at = local_start.isoformat()

        title = (start.group("title") or "").strip()
        if (
            not agenda.title
            and title
            and not title[0].isdigit()
            and not re.match(r"^(тривалість|duration|for\b)", title, re.IGNORECASE)
        ):
            agenda.title = title

    # The LLM can occasionally emit the same explicit action twice.
    # Keep only one copy, preserving the first occurrence.
    unique_actions = []
    seen_tasks: set[str] = set()

    for action in agenda.action_items:
        key = re.sub(r"\s+", " ", action.task).strip().casefold()
        if key in seen_tasks:
            continue
        seen_tasks.add(key)
        unique_actions.append(action)

    agenda.action_items = unique_actions

    # Resolve an explicitly stated relative deadline.
    deadlines = list(DUE_PATTERN.finditer(text))
    due = deadlines[0] if len(deadlines) == 1 else None
    due_weekday: int | None = None

    if due:
        token = (due.group("ua") or due.group("en")).lower()
        due_weekday = DUE_WEEKDAYS[token]
    elif re.search(r"by (?:the )?end of (?:the )?week|до кінця тижня", text, re.IGNORECASE):
        due_weekday = 4  # Product convention: end of the working week is Friday.
    elif re.search(r"\bдо\s+пьятниці\b", text, re.IGNORECASE):
        # Tolerate this common misspelling without asking the LLM to guess.
        due_weekday = 4

    if due_weekday is not None and len(agenda.action_items) == 1:
        agenda.action_items[0].due = next_weekday(today, due_weekday)

    # Fill a missing owner only when the owner's name is explicitly present
    # both in an agenda item and at the beginning of the action text.
    for action in agenda.action_items:
        if action.owner is not None:
            continue

        candidates = {
            item.owner
            for item in agenda.items
            if item.owner
            and action.task.casefold().startswith(item.owner.casefold() + " ")
            and re.search(rf"\b{re.escape(item.owner)}\b", text, re.IGNORECASE)
        }

        if len(candidates) == 1:
            action.owner = next(iter(candidates))

    return agenda
