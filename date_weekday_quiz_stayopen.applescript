#!/usr/bin/osascript
-- Date → Weekday Quiz (Stay‑Open AppleScript)
-- Shows the quiz at login and again after each wake from sleep.

property lastWakeSig : ""
property checkIntervalSeconds : 5
property isShowingQuiz : false

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
        do shell script "printf %s\\n " & quoted form of (lineText as string) & " >> " & quoted form of lf
    end try
end appendLog

on formatSeconds(n)
    set n to n as real
    set tenthsInt to (n * 10) as integer
    set rounded to tenthsInt / 10.0
    return rounded as string
end formatSeconds

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
        set r to display dialog dlgText default answer "" with icon note buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel"
        return text returned of r
    on error number -128
        return missing value
    end try
end promptForWeekday

on runQuiz()
    set targetCorrect to 3
    set score to 0
    set attempts to 0
    set timesSec to {}

    set sessionStartDate to (current date)
    set sessionStartIso to my isoTimestamp(sessionStartDate)
    my appendLog("session_start\ttimestamp=" & sessionStartIso)

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
                set qElapsed to ((current date) - qStart) as real
                set endIso to my isoTimestamp(current date)
                set sr to 0
                if attempts > 0 then set sr to (score / attempts) * 100
                my appendLog("question\ttimestamp=" & endIso & "\tstatus=cancelled\telapsed_s=" & my formatSeconds(qElapsed) & "\tshown=\"" & shown & "\"\tcorrect=\"" & correct & "\"\tscore=" & score & "\tattempts=" & attempts & "\tsuccess_rate_pct=" & (sr as string))

                set timesStrings to {}
                repeat with t in timesSec
                    set end of timesStrings to my formatSeconds(t)
                end repeat
                set summaryTimes to my joinWithCommas(timesStrings)
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
                return
            end if
            set typed to a
            set canon to normalizedWeekdayName(a)
            if canon is "" then
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
            display alert "Correct" message msg as informational buttons {"OK"} default button "OK"
        else
            set msg to ("You answered: " & typed & return & "For " & shown & ", correct is: " & correct & ".")
            display alert "Incorrect" message msg as warning buttons {"OK"} default button "OK"
        end if

        set sr to (score / attempts) * 100
        my appendLog("question\ttimestamp=" & endIso & "\tstatus=" & (wasCorrect as string) & "\telapsed_s=" & my formatSeconds(qElapsed) & "\tanswer=\"" & typed & "\"\tnormalized=\"" & canon & "\"\tshown=\"" & shown & "\"\tcorrect=\"" & correct & "\"\tscore=" & score & "\tattempts=" & attempts & "\tsuccess_rate_pct=" & (sr as string))
    end repeat

    set endIso to my isoTimestamp(current date)
    set timesStrings to {}
    repeat with t in timesSec
        set end of timesStrings to my formatSeconds(t)
    end repeat
    set summaryTimes to my joinWithCommas(timesStrings)
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
    my appendLog("session_end\ttimestamp=" & endIso & "\tstatus=completed\ttotal_questions=" & attempts & "\tcorrect=" & score & "\tsuccess_rate_pct=" & (sr as string) & "\tavg_elapsed_s=" & my formatSeconds(avg))
end runQuiz

on getLastWakeSignature()
    -- Extract timestamp of the most recent Wake event from pmset log
    try
        set cmd to "pmset -g log | egrep -i ' Wake |Wake from' | tail -1 | sed -E 's/^([0-9-]+ [0-9:]+).*/\\1/'"
        set sig to do shell script cmd
        return sig
    on error
        return ""
    end try
end getLastWakeSignature

on run
    -- Initialize last wake signature and show once at login
    set lastWakeSig to getLastWakeSignature()
    set isShowingQuiz to true
    my runQuiz()
    set isShowingQuiz to false
end run

on idle
    try
        set sig to getLastWakeSignature()
        if sig is not "" and sig is not lastWakeSig then
            set lastWakeSig to sig
            if not isShowingQuiz then
                set isShowingQuiz to true
                my runQuiz()
                set isShowingQuiz to false
            end if
        end if
    end try
    return checkIntervalSeconds
end idle
