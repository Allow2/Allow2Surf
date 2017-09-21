-- Opens Organizer, exports ad hoc build
-- Designed for a build mac that only does Brave builds
-- That is, doesn't handle multiple developer IDs, doesn't handle different apps in the Organizer list (otherwise we need another step to pick Brave)
-- NOTE: first time running these, you must have System Preferences>Security & Privacy>Privacy>Accessibility open to get a prompt to allow Xcode

tell application "Xcode"
    activate
end tell
tell application "System Events"
    tell menu item "Organizer" of menu "Window" of menu bar item "Window" of menu bar 1 of process "Xcode"
        perform action "AXPress"
    end tell
end tell

tell application "System Events" to tell process "Xcode"
    tell window "Organizer"
        
        tell scroll area 3 of splitter group 1
            log (properties of UI elements)
            tell button "Export…"
                perform action "AXPress"
            end tell
        end tell
        
        tell UI element 1 of row 2 of table 1 of scroll area 1 of sheet 1
            tell radio button "Save for Ad Hoc Deployment"
                perform action "AXPress"
            end tell
        end tell
        
        tell button "Next" of sheet 1
            perform action "AXPress"
        end tell
        delay 1
        tell button "Choose" of sheet 1 of sheet 1
            perform action "AXPress"
        end tell
        delay 1
        tell button "Next" of sheet 1
            perform action "AXPress"
        end tell
        delay 3
        tell button "Next" of sheet 1
            perform action "AXPress"
        end tell
        
        repeat until exists button "Export" of sheet 1 of sheet 1
            delay 3
        end repeat
        tell button "Export" of sheet 1 of sheet 1
            perform action "AXPress"
        end tell
        
    end tell
end tell

