tell application "Terminal"
    set homePath to POSIX path of (path to home folder)
    set bridgeCommand to "nohup " & quoted form of (homePath & ".local/bin/mac-mouse-bridge") & " >" & quoted form of (homePath & ".config/mac-mouse-bridge.log") & " 2>&1 & exit"
    set bridgeTab to do script bridgeCommand
    delay 0.4
    try
        set visible of (window of bridgeTab) to false
    end try
end tell
