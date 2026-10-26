use framework "Foundation"
use scripting additions

-- Exercise a compiled copy of the real app. The child script replaces every UI
-- and logging handler, so these tests never start a quiz or write practice data.
property assertionCount : 0

on assertEqual(actualValue, expectedValue, descriptionText)
    if actualValue is not equal to expectedValue then
        error descriptionText & ": expected " & (expectedValue as string) & ", got " & (actualValue as string)
    end if
    set assertionCount to assertionCount + 1
end assertEqual

on fixtureDate(secondsAfterMidnight)
    set d to (current date)
    set day of d to 1
    set month of d to January
    set year of d to 2026
    set day of d to 15
    set time of d to secondsAfterMidnight
    return d
end fixtureDate

on hasFragment(linesList, fragmentText)
    repeat with aLine in linesList
        if (contents of aLine) contains fragmentText then return true
    end repeat
    return false
end hasFragment

on registryFixture(isConsole, isLoggedIn, userLocked, rootLocked)
    set userInfo to current application's NSMutableDictionary's dictionary()
    if isConsole is not missing value then userInfo's setObject:isConsole forKey:"kCGSSessionOnConsoleKey"
    if isLoggedIn is not missing value then userInfo's setObject:isLoggedIn forKey:"kCGSessionLoginDoneKey"
    if userLocked is not missing value then userInfo's setObject:userLocked forKey:"CGSSessionScreenIsLocked"
    set rootInfo to current application's NSMutableDictionary's dictionary()
    rootInfo's setObject:(current application's NSArray's arrayWithObject:userInfo) forKey:"IOConsoleUsers"
    if rootLocked is not missing value then rootInfo's setObject:rootLocked forKey:"IOConsoleLocked"
    return rootInfo
end registryFixture

on run argv
    set compiledScriptFile to (POSIX file (item 1 of argv)) as alias
    set sourceScript to load script compiledScriptFile
    script appUnderTest
        property parent : sourceScript
        property answers : {}
        property promptCount : 0
        property recordedLogs : {}
        property recordedAlerts : {}
        property completedSlots : {}
        property stateSaveCount : 0
        property menuUpdateCount : 0
        property presentedSlots : {}
        property uiAvailableFlag : true
        on resetMocks(answerList)
            set answers to answerList
            set promptCount to 0
            set recordedLogs to {}
            set recordedAlerts to {}
            set completedSlots to {}
            set uiUnavailable to false
        end resetMocks
        on ensureFrontmost()
            return
        end ensureFrontmost
        on appendLog(lineText)
            set end of recordedLogs to lineText
        end appendLog
        on displayQuizAlert(titleText, messageText, isWarning)
            set end of recordedAlerts to {titleText, messageText, isWarning}
        end displayQuizAlert
        on sessionDidComplete(slotName)
            set end of completedSlots to slotName
        end sessionDidComplete
        on saveState(nowDate)
            set stateSaveCount to stateSaveCount + 1
        end saveState
        on updateStatusMenu()
            set menuUpdateCount to menuUpdateCount + 1
        end updateStatusMenu
        on isUIAvailable()
            return uiAvailableFlag
        end isUIAvailable
        on presentSession(slotName)
            set end of presentedSlots to slotName
        end presentSession
        on randomDateLast100Years()
            set d to (current date)
            set day of d to 1
            set month of d to January
            set year of d to 2024
            set time of d to (12 * hours)
            return d -- Monday, 1 January 2024
        end randomDateLast100Years
        on promptForWeekday(shownDate, questionNumber, targetQuestions)
            set promptCount to promptCount + 1
            if promptCount > (count of answers) then error "Quiz requested more answers than the test supplied"
            return item promptCount of answers
        end promptForWeekday
    end script

    script persistedApp
        property parent : sourceScript
        property testStatePath : ""
        on stateFilePath()
            return testStatePath
        end stateFilePath
        on updateStatusMenu()
            return
        end updateStatusMenu
        on appendLog(lineText)
            return
        end appendLog
    end script
    set persistedApp's testStatePath to item 2 of argv

    my assertEqual(appUnderTest's registryUIAvailable(missing value), false, "Missing registry data defers prompting")
    my assertEqual(appUnderTest's registryUIAvailable(current application's NSDictionary's dictionary()), false, "Missing console users defers prompting")
    my assertEqual(appUnderTest's registryUIAvailable(current application's NSArray's array()), false, "Empty registry array defers prompting")
    set unlockedRoot to my registryFixture(true, true, missing value, false)
    my assertEqual(appUnderTest's registryUIAvailable(unlockedRoot), true, "Dictionary-shaped registry with an unlocked console is available")
    my assertEqual(appUnderTest's registryUIAvailable(current application's NSArray's arrayWithObject:unlockedRoot), true, "Array-shaped registry is also supported")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(true, true, missing value, true)), false, "Root console-lock flag blocks prompting even without a user lock flag")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(true, true, false, true)), false, "Root lock takes precedence over unlocked user")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(true, true, true, false)), false, "User lock flag blocks prompting")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(true, true, false, missing value)), true, "Unlocked user works without a root lock flag")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(false, true, false, false)), false, "A non-console session cannot receive prompts")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(true, false, false, false)), false, "A session still logging in cannot receive prompts")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(missing value, true, false, false)), false, "Missing on-console flag defers prompting")
    my assertEqual(appUnderTest's registryUIAvailable(my registryFixture(true, missing value, false, false)), false, "Missing login-complete flag defers prompting")

    set morningStart to (8 * hours + 55 * minutes)
    set afternoonStart to (13 * hours)
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(0), false, false, missing value, missing value), "", "Midnight does not prompt")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(morningStart - 1), false, false, missing value, missing value), "", "One second before 08:55 does not prompt")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(morningStart), false, false, missing value, missing value), "morning", "08:55 starts the morning window")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(morningStart + 1), false, false, missing value, missing value), "morning", "Returning after 08:55 catches up the morning")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(afternoonStart - 1), false, false, missing value, missing value), "morning", "12:59:59 is still morning")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(afternoonStart), false, false, missing value, missing value), "afternoon", "13:00 starts afternoon and discards missed morning")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(24 * hours - 1), false, false, missing value, missing value), "afternoon", "Late return catches up the afternoon")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(morningStart), true, false, missing value, missing value), "", "Completed morning does not repeat")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(afternoonStart), false, true, missing value, missing value), "", "Completed afternoon does not repeat")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(morningStart), false, true, missing value, missing value), "morning", "Afternoon completion does not suppress morning")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(afternoonStart), true, false, missing value, missing value), "afternoon", "Morning completion does not suppress afternoon")

    set morningSnooze to my fixtureDate(morningStart + 10 * minutes)
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(morningStart + 1), false, false, morningSnooze, missing value), "", "Morning snooze suppresses immediate retry")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(morningStart + 10 * minutes - 1), false, false, morningSnooze, missing value), "", "Morning snooze lasts the full ten minutes")
    my assertEqual(appUnderTest's dueSlot(morningSnooze, false, false, morningSnooze, missing value), "morning", "Morning snooze expires at ten minutes")
    set afternoonSnooze to my fixtureDate(afternoonStart + 10 * minutes)
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(afternoonStart + 10 * minutes - 1), false, false, missing value, afternoonSnooze), "", "Afternoon snooze lasts the full ten minutes")
    my assertEqual(appUnderTest's dueSlot(afternoonSnooze, false, false, missing value, afternoonSnooze), "afternoon", "Afternoon snooze expires at ten minutes")
    set lateMorningSnooze to my fixtureDate(afternoonStart + 5 * minutes)
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(afternoonStart), false, false, lateMorningSnooze, missing value), "afternoon", "Morning snooze cannot postpone the afternoon")
    my assertEqual(appUnderTest's dueSlot(my fixtureDate(afternoonStart + 6 * minutes), false, true, lateMorningSnooze, missing value), "", "Expired morning snooze never resurrects morning after 13:00")
    my assertEqual(appUnderTest's dueSlot(morningSnooze, true, false, morningSnooze, missing value), "", "Completion takes precedence over a snooze deadline")

    appUnderTest's resetMocks({"Tuesday", "Tuesday", "Tuesday"})
    my assertEqual(appUnderTest's runQuiz("morning"), true, "Three wrong answers still complete a session")
    my assertEqual(appUnderTest's promptCount, 3, "All-wrong session asks exactly three questions")
    my assertEqual(my hasFragment(appUnderTest's recordedLogs, "total_questions=3"), true, "Three-answer completion is logged")
    my assertEqual(my hasFragment(appUnderTest's recordedLogs, "correct=0"), true, "All-wrong score is preserved")
    my assertEqual(appUnderTest's completedSlots, {"morning"}, "Three wrong answers mark the correct slot completed")

    appUnderTest's resetMocks({"Monday", "Tuesday", "Monday"})
    my assertEqual(appUnderTest's runQuiz("afternoon"), true, "Mixed answers complete a session")
    my assertEqual(appUnderTest's promptCount, 3, "Mixed session asks exactly three questions")
    my assertEqual(my hasFragment(appUnderTest's recordedLogs, "correct=2"), true, "Mixed score reports two correct")
    my assertEqual(appUnderTest's completedSlots, {"afternoon"}, "Mixed session marks its captured slot completed")

    appUnderTest's resetMocks({"Monday", "Monday", "Monday"})
    my assertEqual(appUnderTest's runQuiz("morning"), true, "Three correct answers complete a session")
    my assertEqual(appUnderTest's promptCount, 3, "All-correct session asks exactly three questions")

    appUnderTest's resetMocks({"nonsense", "Monday", "Tuesday", "Monday"})
    my assertEqual(appUnderTest's runQuiz("morning"), true, "Invalid input is retried before completion")
    my assertEqual(appUnderTest's promptCount, 4, "Invalid input does not count as an answered question")
    my assertEqual(my hasFragment(appUnderTest's recordedLogs, "total_questions=3"), true, "Invalid input is excluded from completion total")

    appUnderTest's resetMocks({"Monday", missing value})
    my assertEqual(appUnderTest's runQuiz("afternoon"), false, "Cancellation before three answers does not complete a session")
    my assertEqual(appUnderTest's promptCount, 2, "Cancellation stops the current quiz immediately")
    my assertEqual(my hasFragment(appUnderTest's recordedLogs, "status=completed"), false, "Cancelled session is never logged as completed")
    my assertEqual(count of appUnderTest's completedSlots, 0, "Cancellation never marks a slot complete")

    -- Date rollover clears yesterday's completion and snoozes, exactly once.
    set appUnderTest's stateDay to "2026-01-14"
    set appUnderTest's morningDone to true
    set appUnderTest's afternoonDone to true
    set appUnderTest's morningSnoozeUntil to morningSnooze
    set appUnderTest's afternoonSnoozeUntil to afternoonSnooze
    set appUnderTest's stateSaveCount to 0
    appUnderTest's rollStateToDate(my fixtureDate(0))
    my assertEqual(appUnderTest's stateDay, "2026-01-15", "Rollover uses the new local calendar day")
    my assertEqual(appUnderTest's morningDone, false, "Rollover clears yesterday's morning completion")
    my assertEqual(appUnderTest's afternoonDone, false, "Rollover clears yesterday's afternoon completion")
    my assertEqual(appUnderTest's morningSnoozeUntil, missing value, "Rollover clears morning snooze")
    my assertEqual(appUnderTest's afternoonSnoozeUntil, missing value, "Rollover clears afternoon snooze")
    my assertEqual(appUnderTest's stateSaveCount, 1, "Rollover persists the reset once")
    set appUnderTest's morningDone to true
    set appUnderTest's morningSnoozeUntil to morningSnooze
    appUnderTest's rollStateToDate(my fixtureDate(morningStart))
    my assertEqual(appUnderTest's morningDone, true, "Same-day polling preserves completion")
    my assertEqual(appUnderTest's morningSnoozeUntil, morningSnooze, "Same-day polling preserves snooze")
    my assertEqual(appUnderTest's stateSaveCount, 1, "Same-day polling does not rewrite state")

    set appUnderTest's stateDay to "2026-01-15"
    set appUnderTest's stateLoaded to true
    set appUnderTest's morningDone to false
    set appUnderTest's afternoonDone to false
    set appUnderTest's morningSnoozeUntil to missing value
    set appUnderTest's afternoonSnoozeUntil to missing value
    appUnderTest's snoozeSlot("morning", my fixtureDate(morningStart))
    my assertEqual(appUnderTest's morningSnoozeUntil, morningSnooze, "Morning snooze handler sets an exact ten-minute deadline")
    my assertEqual(appUnderTest's afternoonSnoozeUntil, missing value, "Morning snooze leaves afternoon untouched")
    appUnderTest's snoozeSlot("afternoon", my fixtureDate(afternoonStart))
    my assertEqual(appUnderTest's afternoonSnoozeUntil, afternoonSnooze, "Afternoon snooze handler sets an exact ten-minute deadline")
    my assertEqual(appUnderTest's morningDone, false, "Snooze does not manufacture morning completion")
    my assertEqual(appUnderTest's afternoonDone, false, "Snooze does not manufacture afternoon completion")

    set appUnderTest's morningSnoozeUntil to missing value
    set appUnderTest's afternoonSnoozeUntil to missing value
    set appUnderTest's scheduleStartedAt to my fixtureDate(22 * hours)
    set appUnderTest's presentedSlots to {}
    appUnderTest's checkSchedule(my fixtureDate(22 * hours))
    my assertEqual(count of appUnderTest's presentedSlots, 0, "First installation at night does not catch up earlier slots")
    set tomorrowMorning to (my fixtureDate(morningStart)) + days
    set appUnderTest's uiAvailableFlag to false
    appUnderTest's checkSchedule(tomorrowMorning)
    my assertEqual(count of appUnderTest's presentedSlots, 0, "A locked Mac defers a due prompt")
    set appUnderTest's uiAvailableFlag to true
    appUnderTest's checkSchedule(tomorrowMorning)
    my assertEqual(appUnderTest's presentedSlots, {"morning"}, "Unlocking at the next scheduled morning presents practice")
    set appUnderTest's morningDone to true
    appUnderTest's checkSchedule(tomorrowMorning + minutes)
    my assertEqual(appUnderTest's presentedSlots, {"morning"}, "Completed morning does not prompt again through scheduler")
    appUnderTest's checkSchedule((my fixtureDate(afternoonStart)) + days)
    my assertEqual(appUnderTest's presentedSlots, {"morning", "afternoon"}, "The next afternoon prompts independently")

    -- A real plist in the runner's temporary directory tests NSDate bridging,
    -- first-install persistence, restart behavior, and the next calendar day.
    set installTime to my fixtureDate(7 * hours)
    persistedApp's loadState(installTime)
    my assertEqual(persistedApp's stateDay, "2026-01-15", "First install creates today's state")
    my assertEqual(persistedApp's scheduleStartedAt, installTime, "First install records the schedule start")
    my assertEqual(persistedApp's morningDone, false, "First install leaves morning incomplete")
    my assertEqual(persistedApp's afternoonDone, false, "First install leaves afternoon incomplete")
    set persistedApp's morningDone to true
    set persistedApp's afternoonSnoozeUntil to afternoonSnooze
    persistedApp's saveState(my fixtureDate(9 * hours))
    -- Deliberately destroy in-memory values: the next load must recover disk data.
    set persistedApp's morningDone to false
    set persistedApp's afternoonSnoozeUntil to missing value
    set persistedApp's scheduleStartedAt to my fixtureDate(22 * hours)
    persistedApp's loadState(my fixtureDate(9 * hours))
    my assertEqual(persistedApp's morningDone, true, "Restart preserves morning completion")
    my assertEqual(persistedApp's afternoonDone, false, "Restart preserves afternoon incompletion")
    my assertEqual(persistedApp's afternoonSnoozeUntil, afternoonSnooze, "Restart preserves the exact snooze date")
    my assertEqual(persistedApp's scheduleStartedAt, installTime, "Restart preserves the original install time")
    my assertEqual(persistedApp's stateLoaded, true, "Restart marks state loaded")
    set nextDay to (my fixtureDate(0)) + days
    persistedApp's loadState(nextDay)
    my assertEqual(persistedApp's stateDay, "2026-01-16", "Restart on a new day updates the saved date")
    my assertEqual(persistedApp's morningDone, false, "Restart on a new day resets morning completion")
    my assertEqual(persistedApp's afternoonDone, false, "Restart on a new day resets afternoon completion")
    my assertEqual(persistedApp's afternoonSnoozeUntil, missing value, "Restart on a new day clears yesterday's snooze")
    my assertEqual(persistedApp's scheduleStartedAt, installTime, "New day retains initial schedule start")
    persistedApp's loadState(nextDay)
    my assertEqual(persistedApp's stateDay, "2026-01-16", "New day reset survives another restart")
    my assertEqual(persistedApp's morningDone, false, "Saved new day remains incomplete after restart")

    set actualNow to current date
    persistedApp's loadState(actualNow)
    set persistedApp's activeSessionDay to persistedApp's isoDate(actualNow - days)
    persistedApp's sessionDidComplete("afternoon")
    my assertEqual(persistedApp's afternoonDone, false, "Yesterday's late session cannot consume today's afternoon slot")
    set persistedApp's activeSessionDay to persistedApp's isoDate(actualNow)
    persistedApp's sessionDidComplete("afternoon")
    my assertEqual(persistedApp's afternoonDone, true, "Today's completed session consumes today's matching slot")
    my assertEqual(persistedApp's morningDone, false, "Completing afternoon leaves morning incomplete")
    persistedApp's loadState(actualNow)
    my assertEqual(persistedApp's afternoonDone, true, "Completion survives a subsequent restart")

    return (assertionCount as string) & " handler assertions passed; no dialogs or practice-log writes."
end run
