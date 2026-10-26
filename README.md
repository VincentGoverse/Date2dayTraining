# Date Weekday Quiz

A small macOS menu bar app for twice-daily doomsday practice. It opens quietly at login and offers practice at **8:55 am** and **1:00 pm**, using the Mac's local time.

The first installation begins with the next scheduled prompt. After that, an interrupted or missed prompt remains available until its practice window ends.

Each prompt offers **Start** or **Snooze 10 minutes**. A session contains exactly **three answered questions**; incorrect answers count toward the three. Timing starts only when a date is shown. Cancelling a session snoozes that practice window for ten minutes.

The app waits while the screen is locked or asleep and checks again when you return. Morning practice is available from 8:55 am until 1:00 pm; afternoon practice is available from 1:00 pm until midnight. Missed morning sessions expire when the afternoon window starts, so reminders do not stack. Completing a session clears that practice window for the day. Completion and snooze state survive quitting or restarting the app.

## Build and install

Requires macOS, Apple's built-in `osacompile`, and Python 3 for the installer. The quiz itself needs no Python runtime.

```bash
./scripts/build.sh
python3 scripts/install.py --dry-run
python3 scripts/install.py
```

The build compiles a stay-open app, sets a stable bundle identifier, hides the Dock icon, and applies a local ad hoc signature. It does not launch anything. Use `./scripts/build.sh --force` to rebuild an existing build output, or `--output /path/to/Quiz.app` for another output path.

The installer:

- Installs `~/Applications/Date Weekday Quiz.app`.
- Preserves the previous app and its own previous LaunchAgent under `~/Library/Application Support/Date Weekday Quiz/Backups/`.
- Removes copied Finder metadata from the new bundle and verifies its signature before replacing the installed app.
- Registers only `~/Library/LaunchAgents/com.vincentgoverse.dateweekdayquiz.plist` and launches the app quietly through LaunchServices.
- Preserves any existing Login Items and other LaunchAgents.
- Keeps the existing practice log and saved schedule state.

To verify installation without changing login services or processes, install into a mock home:

```bash
python3 scripts/install.py --stage ./build/install-preview
```

`--dry-run` performs no writes. `--no-start` installs the app and login LaunchAgent but leaves the quiz stopped until the next login or manual launch.

## Everyday use

The app stays in the menu bar after login and shows today's completed sessions as `D 0/2`, `D 1/2`, or `D 2/2`. Its menu shows each session's progress and offers **Practice now** and **Quit**. Opening the app from `~/Applications` starts its schedule checks; use **Practice now** for an extra session. **Quit** stops reminders until you reopen it or next log in.

Use number shortcuts `1`–`7` for Monday–Sunday, or full weekday names and common abbreviations, case-insensitively: `Mon`, `Tue`/`Tues`, `Wed`/`Weds`, `Thu`/`Thur`/`Thurs`, `Fri`, `Sat`, and `Sun`. Feedback shows the correct weekday and response time. The final score is the actual result, such as 2/3, followed by the final answer's feedback and all three response times.

Questions show only the date prompt and question number. Click **?** for answer instructions and number shortcuts, then **Back** to return to the same question with your typed answer preserved. Time spent reading help is excluded from the recorded response time.

An unanswered ready prompt closes after one minute and snoozes. An unanswered question closes after two minutes and snoozes the unfinished session. A snoozed unfinished session starts a fresh set of three questions. Feedback and completion dialogs close automatically after 15 seconds.

## Data and source

- Practice history: `~/Library/Logs/Date Weekday Quiz.log` (the existing log continues).
- Daily completion and snooze state: `~/Library/Application Support/Date Weekday Quiz/schedule.plist`.
- Login launcher diagnostics: `~/Library/Logs/Date Weekday Quiz.launcher.log`.
- Scheduled app source: `date_weekday_quiz_stayopen.applescript`.
- One-off quiz source: `date_weekday_quiz.applescript`.

The one-off source runs without installing a login service:

```bash
osascript date_weekday_quiz.applescript
```

To change the schedule or session length, edit the configuration properties near the top of the scheduled source, rebuild, and reinstall. No cron job or Codex automation is used.

Run the noninteractive regression checks with `python3 tests/run_tests.py`. They exercise the real AppleScript handlers with mocked dialogs and temporary state files.

## Troubleshooting and restore

If the app is not running, open `~/Applications/Date Weekday Quiz.app`. If the screen is locked, the app waits for you to unlock it. An app launched after a scheduled time offers only the practice window that is still current.

To inspect the login launch registration:

```bash
launchctl print "gui/$(id -u)/com.vincentgoverse.dateweekdayquiz"
```

The LaunchAgent uses `open` to launch the app and then exits; it is normal for that launcher job to have no active process after a successful launch. The stay-open app owns the schedule.

To stop the managed login launch, quit the app from its menu and run:

```bash
launchctl bootout "gui/$(id -u)/com.vincentgoverse.dateweekdayquiz"
rm "$HOME/Library/LaunchAgents/com.vincentgoverse.dateweekdayquiz.plist"
```

An older Login Item may still open the app at login; remove that specific item in System Settings if you also want to disable it. Other Login Items are preserved by the installer.

For a rollback, quit the app, stop the managed LaunchAgent, and copy the previous app from the timestamped backup over the installed app. Restore the previous LaunchAgent from the same backup if one existed. Practice logs and schedule state are kept separately and are not removed by replacement or rollback.
