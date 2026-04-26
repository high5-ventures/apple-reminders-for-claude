-- get_flagged.applescript
-- Parameters: (none)
-- Returns: {"status":"ok","data":{"reminders":[<reminder>...]}}
--
-- "Flagged" = all open reminders with the flagged property set to true
-- (equivalent to the Flagged smart list in Reminders.app).

set jsonItems to {}

tell application "Reminders"
	set allLists to every list
	repeat with L in allLists
		set lName to name of L
		tell L
			set candidates to reminders whose completed is false and flagged is true
		end tell
		repeat with r in candidates
			set end of jsonItems to my reminderToJson(r, lName)
		end repeat
	end repeat
end tell

return my okResult("{\"reminders\":" & my jsonArray(jsonItems) & "}")
