"""CLI for testing agenda parsing from the laptop."""

import json
import sys
from datetime import datetime

from app.ai.agenda import parse_agenda
from app.config import settings


def main() -> None:
    if len(sys.argv) != 2 or not sys.argv[1].strip():
        raise SystemExit('Usage: python -m app.ai.parse_cli "agenda text"')

    text = sys.argv[1]
    now = datetime.now(settings.tz)

    agenda, usage = parse_agenda(
        text=text,
        today=now.date(),
        tz=settings.app_timezone,
    )

    print(json.dumps(agenda.model_dump(mode="json"), ensure_ascii=False, indent=2))
    print(json.dumps({"usage": usage}, indent=2))


if __name__ == "__main__":
    main()
