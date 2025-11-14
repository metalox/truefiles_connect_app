(*
  Truefiles Connect Ð App version with per-machine config
  Config file: ~/Library/Application Support/Truefiles Connect/config.txt
    - Put SMB URLs one per line (e.g., smb://server/Share Name)
    - Optional directives:
        LOG=on    (enable logging)
        LOG=off   (disable logging; default)
    - Lines starting with # are comments

  Logging (if enabled):  ~/Library/Logs/TruefilesConnect.log
*)

-- ===== App constants (safe compile-time values) =====
property appDisplayName : "Truefiles Connect"
property configFolderName : "Truefiles Connect"
property configFileName : "config.txt"
property defaultLogEnabled : false
property logFileName : "TruefilesConnect.log"

-- ===== Helpers: paths =====
on userAppSupportHFS()
	return (path to application support folder from user domain as text)
end userAppSupportHFS

on userLogsPOSIX()
	return POSIX path of (path to library folder from user domain as text) & "Logs/"
end userLogsPOSIX

on ensureConfigAndMaybeCreateTemplate()
	set cfgDirHFS to (userAppSupportHFS() & configFolderName & ":")
	set cfgFileHFS to (cfgDirHFS & configFileName)
	set cfgDirPOSIX to POSIX path of cfgDirHFS
	set cfgFilePOSIX to POSIX path of cfgFileHFS
	
	-- Ensure directory exists (POSIX)
	do shell script "mkdir -p " & quoted form of cfgDirPOSIX
	
	-- If config exists, return paths
	try
		set _ to (cfgFileHFS as alias)
		return {cfgFileHFS, cfgFilePOSIX, false}
	on error
		-- Create template (POSIX), set permissions, then open with 'open -a'
		set template to "# " & appDisplayName & " configuration" & linefeed & Â
			"# Put one SMB URL per line, for example:" & linefeed & Â
			"#   smb://192.168.61.7/truefiles" & linefeed & Â
			"#   smb://files.company.lan/Media" & linefeed & linefeed & Â
			"# Optional settings:" & linefeed & Â
			"#   LOG=off   (default)" & linefeed & Â
			"#   LOG=on    (enable logging to ~/Library/Logs/TruefilesConnect.log)" & linefeed & linefeed & Â
			"LOG=off" & linefeed & Â
			"smb://192.168.61.7/truefiles" & linefeed
		
		-- Write the file atomically using POSIX tools
		do shell script "/usr/bin/printf %s " & quoted form of template & " > " & quoted form of cfgFilePOSIX
		do shell script "/bin/chmod u+rw " & quoted form of cfgFilePOSIX
		
		-- Try to open with TextEdit via 'open' (more reliable than direct tell)
		try
			do shell script "/usr/bin/open -a TextEdit " & quoted form of cfgFilePOSIX
		on error
			-- Fallback: tell the user where it is
			display dialog "A per-machine config file was created here:" & linefeed & linefeed & cfgFileHFS & linefeed & linefeed & "If it didn't open automatically, open it manually in TextEdit, edit, then run the app again." buttons {"OK"} default button 1 with icon note giving up after 40
		end try
		
		return {cfgFileHFS, cfgFilePOSIX, true}
	end try
end ensureConfigAndMaybeCreateTemplate

-- ===== Helpers: config parsing =====
on trimWhitespace(t)
	set ws to {space, tab, return, linefeed}
	set leftIdx to 1
	repeat while leftIdx ² (length of t) and ((character leftIdx of t) is in ws)
		set leftIdx to leftIdx + 1
	end repeat
	set rightIdx to (length of t)
	repeat while rightIdx ³ leftIdx and ((character rightIdx of t) is in ws)
		set rightIdx to rightIdx - 1
	end repeat
	if rightIdx < leftIdx then return ""
	return text leftIdx thru rightIdx of t
end trimWhitespace

on parseConfig(cfgFileHFS)
	set logEnabled to defaultLogEnabled
	set urls to {}
	
	set rawText to (read (cfgFileHFS as alias) as Çclass utf8È)
	set L to paragraphs of rawText
	repeat with p in L
		set lineTxt to my trimWhitespace(p as text)
		if lineTxt is "" then
			-- skip
		else if lineTxt starts with "#" then
			-- comment
		else if (my toUpper(lineTxt)) is "LOG=ON" then
			set logEnabled to true
		else if (my toUpper(lineTxt)) is "LOG=OFF" then
			set logEnabled to false
		else
			set end of urls to lineTxt
		end if
	end repeat
	
	return {logEnabled, urls}
end parseConfig

on toUpper(t)
	set lc to "abcdefghijklmnopqrstuvwxyz"
	set uc to "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	set out to ""
	repeat with i from 1 to length of t
		set ch to text i of t
		set idx to offset of ch in lc
		if idx is not 0 then
			set out to out & text idx of uc
		else
			set out to out & ch
		end if
	end repeat
	return out
end toUpper

-- ===== Helpers: mount & logging =====
on shareNameOf(u)
	if u does not start with "smb://" then return missing value
	set t to text 7 thru -1 of u
	set AppleScript's text item delimiters to "/"
	set toks to text items of t
	set AppleScript's text item delimiters to ""
	if (count of toks) < 2 then return missing value
	return item 2 of toks
end shareNameOf

on volumeExists(shareName)
	try
		set p to "/Volumes/" & shareName
		set resultText to do shell script "[ -d " & quoted form of p & " ] && echo yes || echo no"
		return (resultText is "yes")
	on error
		return false
	end try
end volumeExists

on writeLogEntry(posixLogPath, theText)
	try
		do shell script "mkdir -p " & quoted form of (do shell script "dirname " & quoted form of posixLogPath) & " ; touch " & quoted form of posixLogPath
		set timeStamp to do shell script "date '+%Y-%m-%d %H:%M:%S'"
		set logLine to timeStamp & "  " & theText & linefeed
		set f to open for access (POSIX file posixLogPath) with write permission
		write logLine to f starting at eof
		close access f
	on error errMsg number errNum
		try
			close access (POSIX file posixLogPath)
		end try
		-- swallow logging errors: the app should still proceed
	end try
end writeLogEntry

-- ===== Main run =====
on run
	-- 1) Ensure config exists (create template if missing)
	set {cfgFileHFS, cfgFilePOSIX, wasCreated} to ensureConfigAndMaybeCreateTemplate()
	if wasCreated then return -- user will edit and rerun
	
	-- 2) Read config
	set {logEnabled, smbTargets} to parseConfig(cfgFileHFS)
	if (count of smbTargets) = 0 then
		display dialog "No SMB shares found in the config file." & linefeed & linefeed & cfgFileHFS buttons {"OK"} default button 1 with icon caution giving up after 40
		return
	end if
	
	-- Log path (only used if enabled)
	set logPathPOSIX to (userLogsPOSIX() & logFileName)
	
	-- 3) Connect
	set connectedList to {}
	set skippedList to {}
	set failedList to {}
	
	repeat with u in smbTargets
		set urlText to (u as text)
		set sName to shareNameOf(urlText)
		if sName is missing value then
			set end of failedList to urlText & " (bad URL)"
		else
			if volumeExists(sName) then
				set end of skippedList to sName
			else
				try
					mount volume urlText
					delay 0.6
					if volumeExists(sName) then
						set end of connectedList to sName
					else
						set end of failedList to sName & " (mounted but not found)"
					end if
				on error errMsg number errNum
					set end of failedList to sName & " (" & errMsg & ")"
				end try
			end if
		end if
	end repeat
	
	-- 4) Summary
	set summaryLines to {}
	if (count of connectedList) > 0 then set end of summaryLines to "Connected: " & (connectedList as text)
	if (count of skippedList) > 0 then set end of summaryLines to "Skipped (already mounted): " & (skippedList as text)
	if (count of failedList) > 0 then set end of summaryLines to "Failed: " & (failedList as text)
	if (count of summaryLines) is 0 then set end of summaryLines to "No shares processed."
	
	set AppleScript's text item delimiters to linefeed
	set msg to summaryLines as text
	set AppleScript's text item delimiters to ""
	
	if logEnabled then writeLogEntry(logPathPOSIX, msg)
	
	set hasFailure to ((count of failedList) > 0)
	if hasFailure then
		display dialog msg buttons {"OK"} default button "OK" with icon caution giving up after 30
	end if
	
	-- Quit the app when done
	quit
end run
