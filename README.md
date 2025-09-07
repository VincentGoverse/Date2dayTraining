# Date to Weekday Training

This repo contains two AppleScript versions of a date→weekday quiz:

- `date_weekday_quiz.applescript`: AppleScript with native macOS dialogs
- `date_weekday_quiz_stayopen.applescript`: AppleScript app that shows the quiz at login and after each wake from sleep (Option A)

Both AppleScript versions:
- Random dates from the last 100 years
- Ask: “What day of the week is YYYY Month D?”
- Accept: full names (e.g. "Monday") or common abbreviations ("Mon", plus variants like "Tues", "Weds", "Thur/Thurs") — case-insensitive
- Show feedback with your score; finish at 3/3
- Cancel quits immediately with a small summary

## Run the AppleScript Version (one‑off)

No dependencies; uses native macOS dialogs.

```bash
osascript date_weekday_quiz.applescript
# or
chmod +x date_weekday_quiz.applescript && ./date_weekday_quiz.applescript
```

Optional: compile the one‑off script to an app you can double‑click:

```bash
mkdir -p "$HOME/Applications"
osacompile -o "$HOME/Applications/Date Weekday Quiz (One-Off).app" date_weekday_quiz.applescript
```
Then launch it from `~/Applications`.

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

- AppleScript permissions: If prompts don’t appear, make sure the app/script isn’t blocked by Focus modes or Screen Time limits.
