-- _prelude.applescript
-- Shared helpers for the apple-reminders skill.
-- Claude concatenates: <parameter block>  +  <script body>  +  <this prelude>
-- AppleScript allows handlers to be called before their textual definition
-- as long as they live in the same top-level script object, so this ordering
-- is safe.

-- ---------------------------------------------------------------------------
-- JSON helpers
-- ---------------------------------------------------------------------------

-- Escape a string for safe inclusion inside a JSON string literal.
on jsonEscape(s)
	if s is missing value then return "null"
	set txt to s as text
	set out to ""
	repeat with i from 1 to length of txt
		set c to character i of txt
		set codePoint to id of c
		if c is "\"" then
			set out to out & "\\\""
		else if c is "\\" then
			set out to out & "\\\\"
		else if codePoint is 10 then
			set out to out & "\\n"
		else if codePoint is 13 then
			set out to out & "\\r"
		else if codePoint is 9 then
			set out to out & "\\t"
		else if codePoint < 32 then
			set out to out & "\\u00" & hex2(codePoint)
		else
			set out to out & c
		end if
	end repeat
	return out
end jsonEscape

on hex2(n)
	set hexChars to "0123456789abcdef"
	set hi to (n div 16) + 1
	set lo to (n mod 16) + 1
	return (character hi of hexChars) & (character lo of hexChars)
end hex2

-- Wrap a string as a JSON string literal (including quotes), or return null.
on jsonString(s)
	if s is missing value then return "null"
	return "\"" & jsonEscape(s) & "\""
end jsonString

-- Wrap a boolean as JSON.
on jsonBool(b)
	if b is missing value then return "null"
	if b then return "true"
	return "false"
end jsonBool

-- Wrap a number as JSON.
on jsonNumber(n)
	if n is missing value then return "null"
	return (n as text)
end jsonNumber

-- Convert an AppleScript date to ISO-8601 (local time, seconds precision).
-- Returns "null" literal if the input is missing value.
on jsonDate(d)
	if d is missing value then return "null"
	set y to year of d
	set m to (month of d) as integer
	set dy to day of d
	set h to hours of d
	set mi to minutes of d
	set se to seconds of d
	return "\"" & y & "-" & pad2(m) & "-" & pad2(dy) & "T" & pad2(h) & ":" & pad2(mi) & ":" & pad2(se) & "\""
end jsonDate

on pad2(n)
	if n < 10 then return "0" & (n as text)
	return (n as text)
end pad2

-- Join a list of already-JSON-serialised strings into a JSON array.
-- Parameter is named `itemList` because `items` is a reserved word in
-- AppleScript and cannot be used as a formal parameter.
on jsonArray(itemList)
	set AppleScript's text item delimiters to ","
	set joined to itemList as text
	set AppleScript's text item delimiters to ""
	return "[" & joined & "]"
end jsonArray

-- ---------------------------------------------------------------------------
-- Reminder serialisation
-- ---------------------------------------------------------------------------

-- Turn one Reminders `reminder` object into a JSON object string.
-- Schema: {"id","name","body","due_date","remind_me_date","completed",
--          "completion_date","priority","flagged","list"}
on reminderToJson(r, listName)
	tell application "Reminders"
		set rid to id of r as text
		set rname to name of r
		try
			set rbody to body of r
		on error
			set rbody to missing value
		end try
		try
			set rdue to due date of r
		on error
			set rdue to missing value
		end try
		try
			set rremind to remind me date of r
		on error
			set rremind to missing value
		end try
		set rcompleted to completed of r
		try
			set rcompdate to completion date of r
		on error
			set rcompdate to missing value
		end try
		set rprio to priority of r
		set rflag to flagged of r
	end tell
	return "{" & ¬
		"\"id\":" & my jsonString(rid) & "," & ¬
		"\"name\":" & my jsonString(rname) & "," & ¬
		"\"body\":" & my jsonString(rbody) & "," & ¬
		"\"due_date\":" & my jsonDate(rdue) & "," & ¬
		"\"remind_me_date\":" & my jsonDate(rremind) & "," & ¬
		"\"completed\":" & my jsonBool(rcompleted) & "," & ¬
		"\"completion_date\":" & my jsonDate(rcompdate) & "," & ¬
		"\"priority\":" & my jsonNumber(rprio) & "," & ¬
		"\"flagged\":" & my jsonBool(rflag) & "," & ¬
		"\"list\":" & my jsonString(listName) & "}"
end reminderToJson

-- Wrap a successful result payload.
on okResult(payloadJson)
	return "{\"status\":\"ok\",\"data\":" & payloadJson & "}"
end okResult

-- Wrap an error payload. `code` is a short machine-readable token,
-- `message` is human-readable.
on errResult(code, message)
	return "{\"status\":\"error\",\"code\":" & my jsonString(code) & ",\"message\":" & my jsonString(message) & "}"
end errResult
