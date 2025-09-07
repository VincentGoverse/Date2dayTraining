#!/usr/bin/env python3
"""
Simple macOS-friendly Tkinter quiz that asks the user to identify
the weekday for random dates from the last 100 years until 3 correct
answers are given.
"""

import csv
import os
import random
import time
from datetime import date, timedelta, datetime
import tkinter as tk
from tkinter import simpledialog, messagebox


# Canonical weekday names (English, not locale-dependent)
WEEKDAY_NAMES = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
]

# Flexible user input → weekday index (0=Sun..6=Sat)
# Accepts common variants like "Tues", "Weds", "Thur", "Thurs".
_SYN_TO_INDEX = {
    # Monday
    "mon": 1, "monday": 1, "m": 1, 
    # Tuesday
    "tue": 2, "tues": 2, "tuesday": 2, 
    # Wednesday
    "wed": 3, "weds": 3, "wednesday": 3, "w": 3,
    # Thursday
    "thu": 4, "thur": 4, "thurs": 4, "thursday": 4,
    # Friday
    "fri": 5, "friday": 5, "f": 5,
    # Saturday
    "sat": 6, "saturday": 6, "sa": 6,
    # Sunday
    "sun": 0, "sunday": 0,  "su": 0,
}


# CSV logging setup
CSV_PATH = os.path.join(os.path.dirname(__file__), "attempts.csv")


def log_attempt(
    started_at_iso: str,
    question: str,
    duration_seconds: float,
    date_iso: str,
    expected_weekday: str,
    answer: str,
    is_correct: bool,
):
    """Append a single attempt row to attempts.csv.

    Columns: started_at, question, duration_seconds, date_iso, expected_weekday, answer, is_correct
    """
    headers = [
        "started_at",
        "question",
        "duration_seconds",
        "date_iso",
        "expected_weekday",
        "answer",
        "is_correct",
    ]

    try:
        needs_header = not os.path.exists(CSV_PATH) or os.path.getsize(CSV_PATH) == 0
        with open(CSV_PATH, "a", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=headers)
            if needs_header:
                w.writeheader()
            w.writerow(
                {
                    "started_at": started_at_iso,
                    "question": question,
                    "duration_seconds": f"{duration_seconds:.3f}",
                    "date_iso": date_iso,
                    "expected_weekday": expected_weekday,
                    "answer": str(answer),
                    "is_correct": "true" if is_correct else "false",
                }
            )
    except Exception:
        # Swallow logging errors to avoid interrupting the quiz UI
        pass


def random_date_last_100_years() -> date:
    """Return a random date within the last ~100 years (inclusive).

    Uses a 100-year window in days to avoid edge cases (e.g., Feb 29).
    """
    today = date.today()
    # ~100 years worth of days (accounts for leap years approximately)
    return today - timedelta(days=random.randint(0, 36525))


def normalize_answer(s: str) -> str:
    """Normalize user input for comparison (case-insensitive, trim spaces/dots)."""
    return s.strip().strip(".").lower()


def answer_to_index(ans: str):
    """Return weekday index for an answer string, or None if unknown."""
    key = normalize_answer(ans)
    return _SYN_TO_INDEX.get(key)


def ask_weekday_dialog(root: tk.Tk, title: str, prompt: str, initial: str = ""):
    """Custom modal dialog to avoid blank prompts on some macOS Tk builds.

    Returns the entered string, or None if cancelled.
    """
    top = tk.Toplevel(root)
    top.title(title)
    top.transient(root)
    top.grab_set()
    try:
        top.attributes("-topmost", True)
    except Exception:
        pass

    # Content
    frm = tk.Frame(top, padx=12, pady=12)
    frm.pack(fill="both", expand=True)

    lbl = tk.Label(frm, text=prompt, anchor="w", justify="left", wraplength=420)
    lbl.pack(fill="x")

    hint = tk.Label(
        frm,
        text="Examples: Mon, Tue, Wed, Thu, Fri, Sat, Sun or full names",
        anchor="w",
        justify="left",
        fg="#666",
        wraplength=420,
    )
    hint.pack(fill="x", pady=(6, 8))

    var = tk.StringVar(value=initial)
    ent = tk.Entry(frm, textvariable=var)
    ent.pack(fill="x")
    ent.focus_set()

    # Buttons
    btns = tk.Frame(frm)
    btns.pack(pady=(10, 0))

    result = {"value": None}

    def on_ok(event=None):
        result["value"] = var.get()
        top.destroy()

    def on_cancel(event=None):
        result["value"] = None
        top.destroy()

    okb = tk.Button(btns, text="OK", width=8, command=on_ok)
    okb.pack(side="left", padx=4)
    ckb = tk.Button(btns, text="Cancel", width=8, command=on_cancel)
    ckb.pack(side="left", padx=4)

    top.bind("<Return>", on_ok)
    top.bind("<Escape>", on_cancel)
    top.protocol("WM_DELETE_WINDOW", on_cancel)

    # Center on screen (best effort)
    top.update_idletasks()
    try:
        sw = top.winfo_screenwidth()
        sh = top.winfo_screenheight()
        w = max(320, top.winfo_reqwidth())
        h = max(140, top.winfo_reqheight())
        x = (sw - w) // 2
        y = (sh - h) // 3
        top.geometry(f"{w}x{h}+{x}+{y}")
    except Exception:
        pass

    root.wait_window(top)
    return result["value"]


def main() -> int:
    # Initialize and hide the root Tk window
    root = tk.Tk()
    root.withdraw()
    try:
        # Try to keep dialogs on top (best effort; may be platform-dependent)
        root.attributes("-topmost", True)
    except Exception:
        pass

    target_correct = 3
    score = 0

    while score < target_correct:
        d = random_date_last_100_years()
        # Convert Python weekday (Mon=0..Sun=6) to our scheme (Sun=0..Sat=6)
        correct_idx = (d.weekday() + 1) % 7  # 0=Sunday .. 6=Saturday
        correct_full = WEEKDAY_NAMES[correct_idx]

        prompt = f"What day of the week is {d.isoformat()}?"

        started_at = datetime.now().isoformat(timespec="seconds")
        t0 = time.perf_counter()

        # Get an answer; allow Cancel to quit gracefully
        while True:
            ans = ask_weekday_dialog(root, "Date → Weekday", prompt)
            if ans is None:
                messagebox.showinfo(
                    "Quit",
                    f"Quiz cancelled. Final score: {score} / {target_correct}",
                    parent=root,
                )
                try:
                    root.destroy()
                except Exception:
                    pass
                return 0
            if normalize_answer(ans) == "":
                messagebox.showinfo(
                    "Answer Required",
                    "Please enter a weekday (e.g., Mon or Monday).",
                    parent=root,
                )
                continue
            break

        duration = time.perf_counter() - t0
        idx = answer_to_index(ans)
        if idx == correct_idx:
            score += 1
            messagebox.showinfo(
                "Correct",
                f"Correct! {score} / {target_correct}\n{d.isoformat()} → {correct_full}",
                parent=root,
            )
            log_attempt(
                started_at_iso=started_at,
                question=prompt,
                duration_seconds=duration,
                date_iso=d.isoformat(),
                expected_weekday=correct_full,
                answer=ans,
                is_correct=True,
            )
        else:
            messagebox.showwarning(
                "Incorrect",
                f"You answered: {ans}\nFor {d.isoformat()}, correct is: {correct_full}.",
                parent=root,
            )
            log_attempt(
                started_at_iso=started_at,
                question=prompt,
                duration_seconds=duration,
                date_iso=d.isoformat(),
                expected_weekday=correct_full,
                answer=ans,
                is_correct=False,
            )

    messagebox.showinfo("All Done", f"All done — {target_correct}/{target_correct}!", parent=root)

    try:
        root.destroy()
    except Exception:
        pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
