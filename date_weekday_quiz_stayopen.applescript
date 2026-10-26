#!/usr/bin/osascript
-- Two daily practice sessions, scheduled in the Mac's local time zone.
use framework "Foundation"
use framework "AppKit"
use scripting additions

property appVersion : "2.0.1"
property morningStartSeconds : (8 * 3600 + 55 * 60)
property afternoonStartSeconds : (13 * 3600)
property snoozeSeconds : 600
property checkIntervalSeconds : 15
property targetQuestions : 3
property stateDay : ""
property morningDone : false
property afternoonDone : false
property morningSnoozeUntil : missing value
property afternoonSnoozeUntil : missing value
property scheduleStartedAt : missing value
property isShowingQuiz : false
property uiUnavailable : false
property questionHelpSeconds : 0
property stateLoaded : false
property activeSessionDay : ""
property statusItem : missing value
property morningMenuItem : missing value
property afternoonMenuItem : missing value

on twoDigits(n)
    return text -2 thru -1 of ("0" & (n as integer as string))
end twoDigits

on isoDate(d)
    return (year of d as integer as string) & "-" & my twoDigits(month of d as integer) & "-" & my twoDigits(day of d)
end isoDate

on isoTimestamp(d)
    set t to time of d
    return my isoDate(d) & " " & my twoDigits(t div hours) & ":" & my twoDigits((t mod hours) div minutes) & ":" & my twoDigits(t mod minutes)
end isoTimestamp

on stateFilePath()
    return (POSIX path of (path to library folder from user domain)) & "Application Support/Date Weekday Quiz/schedule.plist"
end stateFilePath

on logFilePath()
    return (POSIX path of (path to library folder from user domain)) & "Logs/Date Weekday Quiz.log"
end logFilePath

on appendLog(lineText)
    try
        set logsDir to (POSIX path of (path to library folder from user domain)) & "Logs"
        do shell script "/bin/mkdir -p " & quoted form of logsDir
        do shell script "/usr/bin/printf '%s\\n' " & quoted form of (lineText as string) & " >> " & quoted form of my logFilePath()
    end try
end appendLog

on saveState(nowDate)
    set statePath to my stateFilePath()
    set parentPath to (current application's NSString's stringWithString:statePath)'s stringByDeletingLastPathComponent()
    set fm to current application's NSFileManager's defaultManager()
    set madeDir to fm's createDirectoryAtPath:parentPath withIntermediateDirectories:true attributes:(missing value) |error|:(missing value)
    if not (madeDir as boolean) then error "Could not create the practice schedule folder."
    set saved to current application's NSMutableDictionary's dictionary()
    saved's setObject:stateDay forKey:"day"
    saved's setObject:morningDone forKey:"morning_done"
    saved's setObject:afternoonDone forKey:"afternoon_done"
    saved's setObject:scheduleStartedAt forKey:"schedule_started_at"
    if morningSnoozeUntil is not missing value then saved's setObject:morningSnoozeUntil forKey:"morning_snooze_until"
    if afternoonSnoozeUntil is not missing value then saved's setObject:afternoonSnoozeUntil forKey:"afternoon_snooze_until"
    if not ((saved's writeToFile:statePath atomically:true) as boolean) then error "Could not save the practice schedule."
end saveState

on loadState(nowDate)
    -- Do not carry runtime/script-saved properties across process launches.
    set stateDay to ""
    set morningDone to false
    set afternoonDone to false
    set morningSnoozeUntil to missing value
    set afternoonSnoozeUntil to missing value
    set scheduleStartedAt to nowDate
    set statePath to my stateFilePath()
    set fm to current application's NSFileManager's defaultManager()
    set existsAlready to (fm's fileExistsAtPath:statePath) as boolean
    set saved to current application's NSDictionary's dictionaryWithContentsOfFile:statePath
    if saved is not missing value then
        set stateDay to (saved's objectForKey:"day") as string
        set morningDone to (saved's objectForKey:"morning_done") as boolean
        set afternoonDone to (saved's objectForKey:"afternoon_done") as boolean
        set value to saved's objectForKey:"schedule_started_at"
        if value is not missing value then set scheduleStartedAt to value as date
        set value to saved's objectForKey:"morning_snooze_until"
        if value is not missing value then set morningSnoozeUntil to value as date
        set value to saved's objectForKey:"afternoon_snooze_until"
        if value is not missing value then set afternoonSnoozeUntil to value as date
    else if existsAlready then
        -- A damaged file should not silently manufacture completed sessions.
        error "The saved practice schedule could not be read: " & statePath
    end if
    set stateLoaded to true
    my rollStateToDate(nowDate)
end loadState

on rollStateToDate(nowDate)
    set todayKey to my isoDate(nowDate)
    if stateDay is not todayKey then
        set stateDay to todayKey
        set morningDone to false
        set afternoonDone to false
        set morningSnoozeUntil to missing value
        set afternoonSnoozeUntil to missing value
        my saveState(nowDate)
        my updateStatusMenu()
    end if
end rollStateToDate

on dueSlot(nowDate, morningComplete, afternoonComplete, morningDeadline, afternoonDeadline)
    set secondsToday to time of nowDate
    if secondsToday < morningStartSeconds then return ""
    if secondsToday < afternoonStartSeconds then
        if morningComplete then return ""
        if morningDeadline is not missing value then
            if nowDate < morningDeadline then return ""
        end if
        return "morning"
    end if
    if afternoonComplete then return ""
    if afternoonDeadline is not missing value then
        if nowDate < afternoonDeadline then return ""
    end if
    return "afternoon"
end dueSlot

on slotScheduledDate(slotName, nowDate)
    set scheduledDate to nowDate + 0
    if slotName is "morning" then
        set time of scheduledDate to morningStartSeconds
    else
        set time of scheduledDate to afternoonStartSeconds
    end if
    return scheduledDate
end slotScheduledDate

on isUIAvailable()
    -- Read the active console session without requiring Accessibility permission.
    try
        set plistText to do shell script "/usr/sbin/ioreg -n Root -d 1 -a"
        set plistData to (current application's NSString's stringWithString:plistText)'s dataUsingEncoding:(current application's NSUTF8StringEncoding)
        set roots to current application's NSPropertyListSerialization's propertyListWithData:plistData options:0 format:(missing value) |error|:(missing value)
        return my registryUIAvailable(roots)
    on error errMsg number errNum
        my appendLog("error\ttimestamp=" & my isoTimestamp(current date) & "\tcontext=screen_check\terror_number=" & errNum)
    end try
    return false
end isUIAvailable

on registryUIAvailable(registryRoot)
    if registryRoot is missing value then return false
    if (registryRoot's isKindOfClass:(current application's NSDictionary)) as boolean then
        set rootInfo to registryRoot
    else
        if (registryRoot's |count|() as integer) is 0 then return false
        set rootInfo to registryRoot's objectAtIndex:0
    end if
    set consoleLocked to rootInfo's objectForKey:"IOConsoleLocked"
    if consoleLocked is not missing value then
        if consoleLocked as boolean then return false
    end if
    set consoleUsers to rootInfo's objectForKey:"IOConsoleUsers"
    if consoleUsers is missing value then return false
    repeat with userInfo in consoleUsers
        set isConsole to userInfo's objectForKey:"kCGSSessionOnConsoleKey"
        set isLoggedIn to userInfo's objectForKey:"kCGSessionLoginDoneKey"
        if isConsole is not missing value and isLoggedIn is not missing value then
            if (isConsole as boolean) and (isLoggedIn as boolean) then
                set screenLocked to userInfo's objectForKey:"CGSSessionScreenIsLocked"
                if screenLocked is missing value then return true
                return not (screenLocked as boolean)
            end if
        end if
    end repeat
    return false
end registryUIAvailable

on ensureFrontmost()
    current application's NSApp's activateIgnoringOtherApps:true
end ensureFrontmost

on slotLabel(slotName)
    if slotName is "morning" then return "Morning practice"
    if slotName is "afternoon" then return "After-lunch practice"
    return "Extra practice"
end slotLabel

on dailyProgress()
    set morningMark to "○"
    set afternoonMark to "○"
    if morningDone then set morningMark to "✓"
    if afternoonDone then set afternoonMark to "✓"
    return "Morning " & morningMark & "   ·   After lunch " & afternoonMark
end dailyProgress

on setupStatusMenu()
    set statusItem to current application's NSStatusBar's systemStatusBar()'s statusItemWithLength:(current application's NSVariableStatusItemLength)
    set statusMenu to current application's NSMenu's alloc()'s initWithTitle:"Date Weekday Quiz"
    set morningMenuItem to current application's NSMenuItem's alloc()'s initWithTitle:"Morning · 8:55 am" action:(missing value) keyEquivalent:""
    set afternoonMenuItem to current application's NSMenuItem's alloc()'s initWithTitle:"After lunch · 1:00 pm" action:(missing value) keyEquivalent:""
    statusMenu's addItem:morningMenuItem
    statusMenu's addItem:afternoonMenuItem
    statusMenu's addItem:(current application's NSMenuItem's separatorItem())
    set practiceItem to current application's NSMenuItem's alloc()'s initWithTitle:"Practice now" action:"practiceNow:" keyEquivalent:""
    practiceItem's setTarget:me
    statusMenu's addItem:practiceItem
    set quitItem to current application's NSMenuItem's alloc()'s initWithTitle:"Quit Date Weekday Quiz" action:"quitFromMenu:" keyEquivalent:"q"
    quitItem's setTarget:me
    statusMenu's addItem:quitItem
    statusItem's setMenu:statusMenu
    (statusItem's button())'s setToolTip:"Date Weekday Quiz · 8:55 am and 1:00 pm"
    my updateStatusMenu()
end setupStatusMenu

on updateStatusMenu()
    if statusItem is missing value then return
    set completedCount to 0
    set morningTitle to "○ Morning · 8:55 am"
    set afternoonTitle to "○ After lunch · 1:00 pm"
    if morningDone then
        set completedCount to completedCount + 1
        set morningTitle to "✓ Morning · done"
    end if
    if afternoonDone then
        set completedCount to completedCount + 1
        set afternoonTitle to "✓ After lunch · done"
    end if
    (statusItem's button())'s setTitle:("D " & completedCount & "/2")
    morningMenuItem's setTitle:morningTitle
    afternoonMenuItem's setTitle:afternoonTitle
end updateStatusMenu

on snoozeSlot(slotName, nowDate)
    my rollStateToDate(nowDate)
    set deadline to nowDate + snoozeSeconds
    if slotName is "morning" then
        set morningSnoozeUntil to deadline
    else if slotName is "afternoon" then
        set afternoonSnoozeUntil to deadline
    end if
    my saveState(nowDate)
    my appendLog("snoozed\ttimestamp=" & my isoTimestamp(nowDate) & "\tslot=" & slotName & "\tuntil=" & my isoTimestamp(deadline))
end snoozeSlot

on sessionDidComplete(slotName)
    set nowDate to current date
    my rollStateToDate(nowDate)
    -- Finishing yesterday's quiz after midnight must not consume today's slot.
    if stateDay is not activeSessionDay then return
    if slotName is "morning" then
        set morningDone to true
        set morningSnoozeUntil to missing value
    else if slotName is "afternoon" then
        set afternoonDone to true
        set afternoonSnoozeUntil to missing value
    end if
    my saveState(nowDate)
    my updateStatusMenu()
end sessionDidComplete

on promptToStart(slotName)
    try
        my ensureFrontmost()
        set reply to display dialog ((my slotLabel(slotName)) & " · about one minute" & return & "Three questions. Press Return to start." & return & return & my dailyProgress()) with title "Date Weekday Quiz" buttons {"Snooze 10 min", "Start"} default button "Start" cancel button "Snooze 10 min" with icon note giving up after 60
        if gave up of reply then return false
        return (button returned of reply is "Start")
    on error errMsg number errNum
        if errNum is -128 or errNum is -1719 or errNum is -1743 then return false
        error errMsg number errNum
    end try
end promptToStart

on presentSession(slotName)
    set isShowingQuiz to true
    set offeredDay to my isoDate(current date)
    try
        if my promptToStart(slotName) then
            -- A ready dialog can straddle a window/day boundary. Never revive an old slot.
            set nowDate to current date
            my rollStateToDate(nowDate)
            set activeSlot to my dueSlot(nowDate, morningDone, afternoonDone, missing value, missing value)
            if (my isoDate(nowDate)) is offeredDay and (slotName is "extra" or activeSlot is slotName) then
                set didComplete to my runQuiz(slotName)
                if not didComplete and slotName is not "extra" and (my isoDate(current date)) is offeredDay then my snoozeSlot(slotName, current date)
            end if
        else if slotName is not "extra" and (my isoDate(current date)) is offeredDay then
            my snoozeSlot(slotName, current date)
        end if
    on error errMsg number errNum
        my appendLog("error\ttimestamp=" & my isoTimestamp(current date) & "\tcontext=session\terror_number=" & errNum)
        if slotName is not "extra" and (my isoDate(current date)) is offeredDay then
            try
                my snoozeSlot(slotName, current date)
            end try
        end if
    end try
    set isShowingQuiz to false
end presentSession

on checkSchedule(nowDate)
    if isShowingQuiz then return
    if not stateLoaded then my loadState(nowDate)
    my rollStateToDate(nowDate)
    set slotName to my dueSlot(nowDate, morningDone, afternoonDone, morningSnoozeUntil, afternoonSnoozeUntil)
    if slotName is "" then return
    -- First installation starts at the next scheduled time, not a late-night catch-up.
    if (my slotScheduledDate(slotName, nowDate)) < scheduleStartedAt then return
    if not my isUIAvailable() then return
    my presentSession(slotName)
end checkSchedule

on prettyDate(d)
    return (year of d as integer as string) & " " & (month of d as string) & " " & (day of d as string)
end prettyDate

on trimWhitespace(s)
    return ((current application's NSString's stringWithString:(s as string))'s stringByTrimmingCharactersInSet:(current application's NSCharacterSet's whitespaceAndNewlineCharacterSet())) as string
end trimWhitespace

on normalizedWeekdayName(ansText)
    set t to my trimWhitespace(ansText)
    repeat while t ends with "."
        if length of t is 1 then return ""
        set t to text 1 thru -2 of t
    end repeat
    ignoring case
        if t is in {"1", "mon", "monday"} then return "Monday"
        if t is in {"2", "tue", "tues", "tuesday"} then return "Tuesday"
        if t is in {"3", "wed", "weds", "wednesday"} then return "Wednesday"
        if t is in {"4", "thu", "thur", "thurs", "thursday"} then return "Thursday"
        if t is in {"5", "fri", "friday"} then return "Friday"
        if t is in {"6", "sat", "saturday"} then return "Saturday"
        if t is in {"7", "sun", "sunday"} then return "Sunday"
    end ignoring
    return ""
end normalizedWeekdayName

on randomDateLast100Years()
    set d to (current date) - ((random number from 0 to 36525) * days)
    set time of d to 12 * hours
    return d
end randomDateLast100Years

on formatSeconds(n)
    return (((round (n * 10)) / 10) as string)
end formatSeconds

on promptForWeekday(shownDate, questionNumber, totalQuestions)
    set draftAnswer to ""
    try
        repeat
            my ensureFrontmost()
            set reply to display dialog ("What weekday is " & shownDate & "?") with title ("Question " & questionNumber & " of " & totalQuestions) default answer draftAnswer buttons {"?", "Snooze 10 min", "Answer"} default button "Answer" cancel button "Snooze 10 min" giving up after 120
            if gave up of reply then return missing value
            set draftAnswer to text returned of reply
            if button returned of reply is not "?" then return draftAnswer
            set helpStarted to (current application's NSProcessInfo's processInfo()'s systemUptime()) as real
            display alert "How to answer" message ("Enter a weekday name or abbreviation, such as Monday or Mon." & return & return & "Number shortcuts:" & return & "1 Mon · 2 Tue · 3 Wed · 4 Thu · 5 Fri · 6 Sat · 7 Sun") as informational buttons {"Back"} default button "Back" giving up after 60
            set questionHelpSeconds to questionHelpSeconds + ((current application's NSProcessInfo's processInfo()'s systemUptime()) as real) - helpStarted
        end repeat
    on error errMsg number errNum
        if errNum is -128 then return missing value
        if errNum is -1719 or errNum is -1743 then
            set uiUnavailable to true
            return missing value
        end if
        error errMsg number errNum
    end try
end promptForWeekday

on displayQuizAlert(titleText, messageText, isWarning)
    my ensureFrontmost()
    if isWarning then
        display alert titleText message messageText as warning buttons {"OK"} default button "OK" giving up after 15
    else
        display alert titleText message messageText as informational buttons {"OK"} default button "OK" giving up after 15
    end if
end displayQuizAlert

on runQuiz(slotName)
    set uiUnavailable to false
    set score to 0
    set attempts to 0
    set timesSec to {}
    set activeSessionDay to my isoDate(current date)
    set sessionID to (current application's NSUUID's UUID()'s UUIDString()) as string
    set sessionFields to "\tsession_id=" & sessionID & "\tslot=" & slotName & "\tsession_day=" & activeSessionDay & "\tapp_version=" & appVersion
    my appendLog("session_start\ttimestamp=" & my isoTimestamp(current date) & sessionFields)
    repeat while attempts < targetQuestions
        set d to my randomDateLast100Years()
        set shown to my prettyDate(d)
        set correct to weekday of d as string
        set canon to ""
        set typed to ""
        set questionHelpSeconds to 0
        set questionStarted to (current application's NSProcessInfo's processInfo()'s systemUptime()) as real
        repeat
            set a to my promptForWeekday(shown, attempts + 1, targetQuestions)
            if a is missing value then
                set elapsed to ((current application's NSProcessInfo's processInfo()'s systemUptime()) as real) - questionStarted - questionHelpSeconds
                my appendLog("question\ttimestamp=" & my isoTimestamp(current date) & "\tstatus=cancelled\telapsed_s=" & my formatSeconds(elapsed) & "\tshown=\"" & shown & "\"\tcorrect=\"" & correct & "\"\tscore=" & score & "\tattempts=" & attempts & sessionFields)
                my logSessionEnd("cancelled", score, attempts, timesSec, sessionFields)
                return false
            end if
            set typed to my trimWhitespace(a)
            set canon to my normalizedWeekdayName(typed)
            if canon is not "" then exit repeat
            my displayQuizAlert("Weekday required", "Enter 1–7, a weekday name, or an abbreviation such as Mon.", false)
        end repeat
        set elapsed to ((current application's NSProcessInfo's processInfo()'s systemUptime()) as real) - questionStarted - questionHelpSeconds
        set attempts to attempts + 1
        set end of timesSec to elapsed
        set wasCorrect to (canon is correct)
        if wasCorrect then set score to score + 1
        set sr to 100 * score / attempts
        -- Persist the answer before a feedback dialog can block or the app can quit.
        my appendLog("question\ttimestamp=" & my isoTimestamp(current date) & "\tstatus=" & (wasCorrect as string) & "\telapsed_s=" & my formatSeconds(elapsed) & "\tanswer=\"" & typed & "\"\tnormalized=\"" & canon & "\"\tshown=\"" & shown & "\"\tcorrect=\"" & correct & "\"\tscore=" & score & "\tattempts=" & attempts & "\tsuccess_rate_pct=" & my formatSeconds(sr) & sessionFields)
        if attempts < targetQuestions then
            if wasCorrect then
                my displayQuizAlert("Correct", shown & " → " & correct & return & my formatSeconds(elapsed) & " seconds · Question " & attempts & " of " & targetQuestions, false)
            else
                my displayQuizAlert("Incorrect", shown & " → " & correct & return & "You answered " & typed & "." & return & my formatSeconds(elapsed) & " seconds", true)
            end if
        end if
    end repeat
    my logSessionEnd("completed", score, attempts, timesSec, sessionFields)
    my sessionDidComplete(slotName)
    set lastResult to "Correct"
    if not wasCorrect then set lastResult to "Incorrect"
    set timeStrings to {}
    repeat with t in timesSec
        set end of timeStrings to my formatSeconds(t)
    end repeat
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to ", "
    set summaryTimes to timeStrings as string
    set AppleScript's text item delimiters to oldDelimiters
    set summary to (score as string) & " / " & targetQuestions & " correct" & return & "Last answer: " & lastResult & " · " & shown & " → " & correct & return & "Times (seconds): " & summaryTimes & return & my dailyProgress()
    my displayQuizAlert("Session complete", summary, false)
    return true
end runQuiz

on logSessionEnd(resultStatus, score, attempts, timesSec, sessionFields)
    set avg to 0
    set sr to 0
    if attempts > 0 then
        set totalTime to 0
        repeat with t in timesSec
            set totalTime to totalTime + t
        end repeat
        set avg to totalTime / attempts
        set sr to 100 * score / attempts
    end if
    my appendLog("session_end\ttimestamp=" & my isoTimestamp(current date) & "\tstatus=" & resultStatus & "\ttotal_questions=" & attempts & "\tcorrect=" & score & "\tsuccess_rate_pct=" & my formatSeconds(sr) & "\tavg_elapsed_s=" & my formatSeconds(avg) & sessionFields)
end logSessionEnd

on practiceNow:sender
    if isShowingQuiz then return
    set nowDate to current date
    my rollStateToDate(nowDate)
    set slotName to my dueSlot(nowDate, morningDone, afternoonDone, missing value, missing value)
    if slotName is "" then set slotName to "extra"
    my presentSession(slotName)
end practiceNow:

on quitFromMenu:sender
    tell me to quit
end quitFromMenu:

on run
    set isShowingQuiz to false
    set statusItem to missing value
    set morningMenuItem to missing value
    set afternoonMenuItem to missing value
    set nowDate to current date
    my loadState(nowDate)
    my setupStatusMenu()
    my appendLog("app_started\ttimestamp=" & my isoTimestamp(nowDate) & "\tapp_version=" & appVersion & "\tmorning=08:55\tafternoon=13:00")
    my checkSchedule(nowDate)
end run

on reopen
    -- A Login Item and our login launcher may both open the same app. Treat
    -- reopen as a schedule check, so duplicate launches cannot start extra quizzes.
    if not isShowingQuiz then my checkSchedule(current date)
end reopen

on idle
    try
        my checkSchedule(current date)
    on error errMsg number errNum
        my appendLog("error\ttimestamp=" & my isoTimestamp(current date) & "\tcontext=scheduler\terror_number=" & errNum)
    end try
    return checkIntervalSeconds
end idle

on quit
    if statusItem is not missing value then current application's NSStatusBar's systemStatusBar()'s removeStatusItem:statusItem
    set statusItem to missing value
    set morningMenuItem to missing value
    set afternoonMenuItem to missing value
    continue quit
end quit
