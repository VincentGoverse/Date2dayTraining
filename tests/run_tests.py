#!/usr/bin/env python3
"""Compile the app and exercise its real handlers without dialogs or file writes."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="date-weekday-tests-") as scratch:
    compiled = Path(scratch) / "quiz.scpt"
    subprocess.run(
        ["osacompile", "-o", str(compiled), str(ROOT / "date_weekday_quiz_stayopen.applescript")],
        check=True,
    )
    subprocess.run(
        ["osascript", str(Path(__file__).with_name("handlers.applescript")), str(compiled), str(Path(scratch) / "schedule.plist")],
        check=True,
    )
