# Date to Weekday Training

This repo contains two Mac-friendly versions of a date→weekday quiz:

- `date_weekday_quiz.py`: Python 3 + Tkinter dialogs
- `date_weekday_quiz.applescript`: AppleScript with native macOS dialogs
- `date_weekday_quiz_stayopen.applescript`: AppleScript app that shows the quiz at login and after each wake from sleep (Option A)

Both versions:
- Random dates from the last 100 years
- Ask: “What day of the week is YYYY Month D?”
- Accept: full names (e.g. "Monday") or common abbreviations ("Mon", plus variants like "Tues", "Weds", "Thur/Thurs") — case-insensitive
- Show feedback with your score; finish at 10/10
- Cancel quits immediately with a small summary

## Run the Python Version

Requirements: macOS with Python 3. Tkinter is built-in. Some systems print a Tk deprecation warning; it is safe to ignore.

Run from the project folder:

```bash
python3 date_weekday_quiz.py
# or
chmod +x date_weekday_quiz.py && ./date_weekday_quiz.py
```

Optional: suppress the Tk deprecation warning on macOS

```bash
TK_SILENCE_DEPRECATION=1 python3 date_weekday_quiz.py
```

Notes:
- Dialogs stay on top; prompt shows the date clearly.
- Press Enter to submit, Esc/Cancel to quit.

## Run the AppleScript Version (one‑off)

No dependencies; uses native macOS dialogs.

```bash
osascript date_weekday_quiz.applescript
# or
chmod +x date_weekday_quiz.applescript && ./date_weekday_quiz.applescript
```

## Run at Login and After Wake (Option A)

Use the stay‑open AppleScript as a small background app that:
- Runs the quiz once at login
- Detects wake-from-sleep and shows the quiz again

1) Compile it to an app:

```bash
mkdir -p "$HOME/Applications"
osacompile -o "$HOME/Applications/Date Weekday Quiz.app" date_weekday_quiz_stayopen.applescript
```

2) Add to Login Items:
- System Settings → General → Login Items → Open at Login → “+” → pick `Date Weekday Quiz.app`.

3) Test it:
- Double‑click `~/Applications/Date Weekday Quiz.app` to show the quiz.
- Put your Mac to sleep, wake it; within ~20s the quiz appears.

Tweak interval: edit `checkIntervalSeconds` near the top of `date_weekday_quiz_stayopen.applescript`.

Optional (hide Dock icon):

```bash
plutil -replace LSUIElement -bool true "$HOME/Applications/Date Weekday Quiz.app/Contents/Info.plist"
```
Then quit and relaunch the app.

## Input Accepted

- Monday: `Mon`, `Monday`
- Tuesday: `Tue`, `Tues`, `Tuesday`
- Wednesday: `Wed`, `Weds`, `Wednesday`
- Thursday: `Thu`, `Thur`, `Thurs`, `Thursday`
- Friday: `Fri`, `Friday`
- Saturday: `Sat`, `Saturday`
- Sunday: `Sun`, `Sunday`

## Troubleshooting

- Blank Tk dialog (rare on some macOS Tk builds): The Python script uses a custom dialog to ensure the prompt is visible. If you still see blank native message boxes, prefer the AppleScript version.
- Tk deprecation warning: Run with `TK_SILENCE_DEPRECATION=1` or use the AppleScript version.
- AppleScript permissions: If prompts don’t appear, make sure the app/script isn’t blocked by Focus modes or Screen Time limits.
