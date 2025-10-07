#!/usr/bin/osascript
-- Date → Weekday Quiz (Stay‑Open AppleScript)
-- Shows the quiz at login and again after each wake from sleep.

property lastWakeSig : ""
property checkIntervalSeconds : 1
property isShowingQuiz : false
property uiUnavailable : false
property pendingSigLogged : ""

on appProcessName()
    try
        set f to (path to me) as alias
        set finfo to info for f
        set nm to name of finfo
        if nm ends with ".app" then set nm to text 1 thru -5 of nm
        return nm
    on error
        return ""
    end try
end appProcessName

on ensureFrontmost()
    try
        activate
    end try
    try
        set nm to my appProcessName()
        if nm is not "" then
            tell application "System Events" to set frontmost of (first application process whose name is nm) to true
        end if
    end try
end ensureFrontmost

on closeLingeringAlerts()
    -- Dismiss any leftover dialogs from a previous run so we start from a clean state.
    try
        set nm to my appProcessName()
        if nm is "" then return
        tell application "System Events"
            if not (exists process nm) then return
            tell process nm
                repeat with attempt from 1 to 5
                    if (count of windows) is 0 then exit repeat
                    try
                        tell window 1
                            if exists button "OK" then
                                click button "OK"
                            else if (count of buttons) > 0 then
                                click button 1
                            else
                                exit repeat
                            end if
                        end tell
                    on error
                        exit repeat
                    end try
                    delay 0.1
                end repeat
            end tell
        end tell
    end try
end closeLingeringAlerts

on twoDigits(n)
    set n to (n as integer)
    set s to "0" & (n as string)
    return text -2 thru -1 of s
end twoDigits

on isoTimestamp(d)
    set y to year of d as integer
    set m to month of d as integer
    set dd to day of d as integer
    set tSec to time of d as integer
    set hh to (tSec div hours) as integer
    set mm to ((tSec mod hours) div minutes) as integer
    set ss to (tSec mod minutes) as integer
    return (y as string) & "-" & twoDigits(m) & "-" & twoDigits(dd) & " " & twoDigits(hh) & ":" & twoDigits(mm) & ":" & twoDigits(ss)
end isoTimestamp

on prettyDate(d)
    -- Format: YYYY MonthName D (e.g., 2024 September 7)
    set y to year of d as integer
    set mname to month of d as string
    set dd to day of d as integer
    return (y as string) & " " & mname & " " & (dd as string)
end prettyDate

on trimWhitespace(s)
    set t to s as string
    set ws to {space, tab, return, linefeed}
    -- left
    repeat while (t is not "") and (character 1 of t is in ws)
        if (length of t) ≤ 1 then
            set t to ""
            exit repeat
        else
            set t to text 2 thru -1 of t
        end if
    end repeat
    -- right
    repeat while (t is not "") and (character -1 of t is in ws)
        if (length of t) ≤ 1 then
            set t to ""
            exit repeat
        else
            set t to text 1 thru -2 of t
        end if
    end repeat
    return t
end trimWhitespace

on stripTrailingDots(s)
    set t to s as string
    repeat while (t is not "") and (character -1 of t is ".")
        if (length of t) ≤ 1 then
            set t to ""
            exit repeat
        else
            set t to text 1 thru -2 of t
        end if
    end repeat
    return t
end stripTrailingDots

on toLower(s)
    try
        return do shell script "printf %s " & quoted form of (s as string) & " | tr '[:upper:]' '[:lower:]'"
    on error
        -- Fallback: best-effort manual mapping A..Z → a..z
        set t to s as string
        set out to ""
        repeat with i from 1 to count of characters of t
            set ch to character i of t
            set idn to id of ch
            if idn ≥ 65 and idn ≤ 90 then
                set out to out & character id (idn + 32)
            else
                set out to out & ch
            end if
        end repeat
        return out
    end try
end toLower

on logFilePath()
    return (POSIX path of (path to library folder from user domain)) & "Logs/Date Weekday Quiz.log"
end logFilePath

on ensureLogsDir()
    try
        set logsDir to (POSIX path of (path to library folder from user domain)) & "Logs"
        do shell script "mkdir -p " & quoted form of logsDir
    end try
end ensureLogsDir

on appendLog(lineText)
    try
        my ensureLogsDir()
        set lf to my logFilePath()
        do shell script "printf '%s\\n' " & quoted form of (lineText as string) & " >> " & quoted form of lf
    end try
end appendLog

on formatSeconds(n)
    set n to n as real
    set tenthsInt to (n * 10) as integer
    set rounded to tenthsInt / 10.0
    return rounded as string
end formatSeconds

on formatPercent(n)
    set n to n as real
    set tenthsInt to (n * 10) as integer
    set rounded to tenthsInt / 10.0
    return rounded as string
end formatPercent

on joinWithCommas(lst)
    set {oldTID, text item delimiters} to {text item delimiters, ", "}
    try
        set s to lst as string
    on error
        set text item delimiters to oldTID
        error
    end try
    set text item delimiters to oldTID
    return s
end joinWithCommas

on normalizedWeekdayName(ansText)
    set t to stripTrailingDots(trimWhitespace(ansText))
    set t to toLower(t)
    if t is "mon" or t is "monday" then return "Monday"
    if t is "tue" or t is "tues" or t is "tuesday" then return "Tuesday"
    if t is "wed" or t is "weds" or t is "wednesday" then return "Wednesday"
    if t is "thu" or t is "thur" or t is "thurs" or t is "thursday" then return "Thursday"
    if t is "fri" or t is "friday" then return "Friday"
    if t is "sat" or t is "saturday" then return "Saturday"
    if t is "sun" or t is "sunday" then return "Sunday"
    return ""
end normalizedWeekdayName

on randomDateLast100Years()
    set today to (current date)
    set rnd to (random number from 0 to 36525)
    set rndDays to rnd as integer
    set d to today - (rndDays * days)
    -- Normalize to noon to avoid DST quirks
    set time of d to (12 * hours)
    return d
end randomDateLast100Years

on promptForWeekday(shownDate)
    set dlgText to "What day of the week is " & shownDate & "?" & return & "(e.g., Mon or Monday)"
    try
        my ensureFrontmost()
        set r to display dialog dlgText default answer "" with icon note buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel"
        return text returned of r
    on error errMsg number errNum
        if errNum is -128 then
            return missing value
        else if errNum is -1719 or errNum is -1743 then
            set uiUnavailable to true
            return missing value
        else
            error errMsg number errNum
        end if
    end try
end promptForWeekday

on runQuiz()
    set targetCorrect to 3
    set score to 0
    set attempts to 0
    set timesSec to {}

    -- Only log session_start once we actually begin interacting
    set sessionStartDate to missing value
    set sessionStartIso to ""

    repeat while score < targetCorrect
        set qStart to (current date)
        set d to randomDateLast100Years()
        set shown to prettyDate(d)
        set correct to (weekday of d) as string

        -- Ask until we get a non-empty answer or cancel
        set canon to ""
        set typed to ""
        repeat
            set a to promptForWeekday(shown)
            if a is missing value then
                if uiUnavailable then
                    -- UI not available (likely lock screen). Defer quiz without alerts/log spam.
                    set uiUnavailable to false
                    my appendLog("deferred\ttimestamp=" & my isoTimestamp(current date) & "\treason=ui_unavailable")
                    return false
                end if
                set qElapsed to ((current date) - qStart) as real
                set endIso to my isoTimestamp(current date)
                set sr to 0
                if attempts > 0 then set sr to (score / attempts) * 100
                my appendLog("question\ttimestamp=" & endIso & "\tstatus=cancelled\telapsed_s=" & my formatSeconds(qElapsed) & "\tshown=\"" & shown & "\"\tcorrect=\"" & correct & "\"\tscore=" & score & "\tattempts=" & attempts & "\tsuccess_rate_pct=" & my formatPercent(sr))

                set timesStrings to {}
                repeat with t in timesSec
                    set end of timesStrings to my formatSeconds(t)
                end repeat
                set summaryTimes to my joinWithCommas(timesStrings)
                my ensureFrontmost()
                display alert "Quit" message ("Quiz cancelled. Final score: " & score & " / " & targetCorrect & return & "Times (s) per question: " & summaryTimes) as informational buttons {"OK"} default button "OK"

                set avg to 0
                if (count of timesSec) > 0 then
                    set total to 0
                    repeat with t in timesSec
                        set total to total + t
                    end repeat
                    set avg to total / (count of timesSec)
                end if
                my appendLog("session_end\ttimestamp=" & endIso & "\tstatus=cancelled\ttotal_questions=" & attempts & "\tcorrect=" & score & "\tsuccess_rate_pct=" & (sr as string) & "\tavg_elapsed_s=" & my formatSeconds(avg))
                return true
            end if
            -- We are able to interact with UI; mark session start if not yet
            if sessionStartDate is missing value then
                set sessionStartDate to (current date)
                set sessionStartIso to my isoTimestamp(sessionStartDate)
                my appendLog("session_start\ttimestamp=" & sessionStartIso)
            end if

            set typed to a
            set canon to normalizedWeekdayName(a)
            if canon is "" then
                my ensureFrontmost()
                display alert "Answer Required" message "Please enter a weekday (e.g., Mon or Monday)." as informational buttons {"OK"} default button "OK"
            else
                exit repeat
            end if
        end repeat

        set qElapsed to ((current date) - qStart) as real
        set endIso to my isoTimestamp(current date)
        set attempts to attempts + 1
        set end of timesSec to qElapsed

        set wasCorrect to (canon is equal to correct)
        if wasCorrect then
            set score to score + 1
            set msg to ("Correct! " & score & " / " & targetCorrect & return & shown & " → " & correct)
            my ensureFrontmost()
            display alert "Correct" message msg as informational buttons {"OK"} default button "OK"
        else
            set msg to ("You answered: " & typed & return & "For " & shown & ", correct is: " & correct & ".")
            my ensureFrontmost()
            display alert "Incorrect" message msg as warning buttons {"OK"} default button "OK"
        end if

        set sr to (score / attempts) * 100
        my appendLog("question\ttimestamp=" & endIso & "\tstatus=" & (wasCorrect as string) & "\telapsed_s=" & my formatSeconds(qElapsed) & "\tanswer=\"" & typed & "\"\tnormalized=\"" & canon & "\"\tshown=\"" & shown & "\"\tcorrect=\"" & correct & "\"\tscore=" & score & "\tattempts=" & attempts & "\tsuccess_rate_pct=" & my formatPercent(sr))
    end repeat

    set endIso to my isoTimestamp(current date)
    set timesStrings to {}
    repeat with t in timesSec
        set end of timesStrings to my formatSeconds(t)
    end repeat
    set summaryTimes to my joinWithCommas(timesStrings)
    my ensureFrontmost()
    display alert "All Done" message ("All done — " & targetCorrect & "/" & targetCorrect & "!" & return & "Times (s) per question: " & summaryTimes) as informational buttons {"OK"} default button "OK"

    set avg to 0
    if (count of timesSec) > 0 then
        set total to 0
        repeat with t in timesSec
            set total to total + t
        end repeat
        set avg to total / (count of timesSec)
    end if
    set sr to (score / attempts) * 100
    my appendLog("session_end\ttimestamp=" & endIso & "\tstatus=completed\ttotal_questions=" & attempts & "\tcorrect=" & score & "\tsuccess_rate_pct=" & my formatPercent(sr) & "\tavg_elapsed_s=" & my formatSeconds(avg))
    return true
end runQuiz

on getLastWakeSignature()
    -- Prefer a stable kernel wake time; fallback to pmset parsing
    try
        set cmd1 to "sysctl -n kern.waketime | sed -E 's/.*sec = ([0-9]+).*/\\1/'"
        set sig1 to do shell script cmd1
        if sig1 is not "" then return sig1
    end try
    try
        set cmd2 to "pmset -g log | egrep -i ' Wake |Wake from|DarkWake' | tail -1 | sed -E 's/^([0-9-]+ [0-9:]+).*/\\1/'"
        set sig2 to do shell script cmd2
        return sig2
    on error
        return ""
    end try
end getLastWakeSignature

on run
    -- Initialize last wake signature and show once at login
    set lastWakeSig to getLastWakeSignature()
    set isShowingQuiz to true
    try
        my closeLingeringAlerts()
        my runQuiz()
    end try
    set isShowingQuiz to false
end run

on idle
    try
        set sig to getLastWakeSignature()
        if sig is not "" and sig is not lastWakeSig then
            if sig is not pendingSigLogged then
                my appendLog("wake_detected\ttimestamp=" & my isoTimestamp(current date) & "\tpmset_sig=\"" & sig & "\"")
                set pendingSigLogged to sig
            end if
            if not isShowingQuiz then
                set isShowingQuiz to true
                try
                    my closeLingeringAlerts()
                    set didRun to my runQuiz()
                    -- Only consume the wake signature after a successful attempt
                    if didRun is true then
                        set lastWakeSig to sig
                        set pendingSigLogged to ""
                        my appendLog("wake_processed\ttimestamp=" & my isoTimestamp(current date) & "\tpmset_sig=\"" & sig & "\"")
                    end if
                on error
                    -- Do not consume the signature; try again next idle
                end try
                set isShowingQuiz to false
            end if
        end if
    end try
    return checkIntervalSeconds
end idle
