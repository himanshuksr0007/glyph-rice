local vars = require("variables")
local fn   = require("hyprland.functions")

-- shell globals -- shell:<name>: registered by whichever shell is alive (demonshot, galaga); if it lacks one, it stays silent
-- Launcher: tap Super. Since 0.57 binds on the modifier itself do not fire on press or release
-- (hyprwm/Hyprland#15952, #15050), so we catch the Super release by polling the key state instead of bindr.
-- Without swallowing Super+1 it would open the launcher too -- every Super+<key> that is not consumed cancels the tap.
local superDown, superTap = false, false
-- binds on the modifiers themselves are also dead in 0.57, so we watch Super+Shift/Ctrl/Alt here as well
local otherMods = { "Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L", "Alt_R" }
hl.timer(function()
    local down = hl.is_key_down("Super_L") or hl.is_key_down("Super_R")
    if down then
        if not superDown then superDown, superTap = true, true end
        if superTap then
            for _, sym in ipairs(otherMods) do
                if hl.is_key_down(sym) then superTap = false break end
            end
        end
    elseif superDown then
        superDown = false
        local tap = superTap
        superTap = false
        if tap then hl.dispatch(hl.dsp.global("shell:launcher")) end
    end
end, { timeout = 25, type = "repeat" })
for _, key in ipairs({
    -- workspaces
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    -- Super+<key> binds below
    "Q", "W", "E", "R", "T", "A", "D", "F", "G", "K", "L", "C", "V", "M", "N", "P",
    "Z", "X", "U", "S", "H", "I", "space", "Escape",
    "Comma", "Period", "Minus", "Equal", "Backslash", "grave",
    "left", "right", "up", "down",
    "Page_Up", "Page_Down", "F12",
    "mouse:272", "mouse:273", "mouse:274", "mouse:275", "mouse:276", "mouse:277",
    "mouse_up", "mouse_down",
}) do
    hl.bind("SUPER + " .. key, function() superTap = false end, { non_consuming = true })
end

-- Misc
hl.bind(vars.kbAltar, hl.dsp.global("shell:altar"))
hl.bind("SUPER + I", hl.dsp.global("shell:settings"))
hl.bind("SUPER + N", hl.dsp.global("shell:ward"))
hl.bind("SUPER + P", hl.dsp.global("shell:pact"))
hl.bind("SUPER + A", hl.dsp.global("shell:quick")) -- galaga quick settings
hl.bind("SUPER + Tab", hl.dsp.global("shell:desktops")) -- desktops overview (also 3-finger swipe up)
hl.bind("SUPER + grave", hl.dsp.global("shell:expose")) -- exposé: every window on this desktop (galaga only)
hl.bind("SUPER + SHIFT + W", hl.dsp.global("shell:wall")) -- galaga wallpapers
hl.bind(vars.kbSession, hl.dsp.global("shell:power"))
hl.bind(vars.kbPower, hl.dsp.global("shell:power"))
hl.bind(vars.kbLock, hl.dsp.exec_cmd(vars.lockCmd))
hl.bind(vars.kbRestoreLock, hl.dsp.exec_cmd(vars.lockCmd), { locked = true }) -- lock crashed -- start it again (session still locked -> needs locked)

-- Brightness: handled by the shell (services/Backlight) -- the OSD moves instantly, brightnessctl catches up
hl.bind("XF86MonBrightnessUp", hl.dsp.global("shell:briUp"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("shell:briDown"), { locked = true, repeating = true })

-- Media
hl.bind("CTRL + SUPER + Space", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("CTRL + SUPER + Equal", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("CTRL + SUPER + Minus", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"), { locked = true })

-- Kill/restart
hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd(vars.rice .. " kill"), { release = true })
hl.bind("CTRL + SUPER + ALT + R", hl.dsp.exec_cmd(vars.rice .. " restart"), { release = true })

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(vars.kbGoToWs .. " + " .. key, fn.wsaction("focus", "", i))
    hl.bind(vars.kbMoveWinToWs .. " + " .. key, fn.wsaction("move", "", i))
    hl.bind(vars.kbGoToWsGroup .. " + " .. key, fn.wsaction("focus", "group", i))
    hl.bind(vars.kbMoveWinToWsGroup .. " + " .. key, fn.wsaction("move", "group", i))
end

-- Go to workspace -1/+1
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "-1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "+1" }))
hl.bind(vars.kbPrevWs, hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind(vars.kbNextWs, hl.dsp.focus({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + Page_Up", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + Page_down", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Go to workspace group -1/+1
hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "-10" }))
hl.bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "+10" }))

-- Move window to workspace -1/+1
hl.bind("SUPER + ALT + Page_Up", hl.dsp.window.move({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + ALT + Page_Down", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + ALT + mouse_down", hl.dsp.window.move({ workspace = "-1" }))
hl.bind("SUPER + ALT + mouse_up", hl.dsp.window.move({ workspace = "+1" }))
hl.bind("CTRL + SUPER + SHIFT + right", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("CTRL + SUPER + SHIFT + left", hl.dsp.window.move({ workspace = "-1" }), { repeating = true })

-- Move window to/from special workspace
hl.bind("CTRL + SUPER + SHIFT + up", hl.dsp.window.move({ workspace = "special:special" }))
hl.bind("CTRL + SUPER + SHIFT + down", hl.dsp.window.move({ workspace = "e+0" }))
hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special" }))

-- Window groups
hl.bind(vars.kbWindowGroupCycleNext, hl.dsp.window.cycle_next(), { repeating = true })
hl.bind(vars.kbWindowGroupCyclePrev, hl.dsp.window.cycle_next({ next = false }), { repeating = true })
hl.bind("CTRL + ALT + Tab", hl.dsp.group.next(), { repeating = true })
hl.bind("CTRL + SHIFT + ALT + Tab", hl.dsp.group.prev(), { repeating = true })
hl.bind(vars.kbToggleGroup, hl.dsp.group.toggle())
hl.bind(vars.kbUngroup, hl.dsp.window.move({ out_of_group = true }))
-- group.lock() only took over lock_active()'s meaning in 0.57; on 0.56 lock() is the all-groups lock
local kbLockGroup = hl.version():match("^0%.5[0-6]%.") and hl.dsp.group.lock_active() or hl.dsp.group.lock()
hl.bind("SUPER + SHIFT + Comma", kbLockGroup)

-- Window actions
-- super+arrows snap (the shell's snap service); snapping off in
-- settings -> windows and the service moves focus instead, as these used to
hl.bind("SUPER + left", hl.dsp.global("shell:snapleft"))
hl.bind("SUPER + right", hl.dsp.global("shell:snapright"))
hl.bind("SUPER + up", hl.dsp.global("shell:snapup"))
hl.bind("SUPER + down", hl.dsp.global("shell:snapdown"))
hl.bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "down" }))
hl.bind("SUPER + Minus", hl.dsp.window.resize(fn.resize_active_window(-10, 0)), { repeating = true })
hl.bind("SUPER + Equal", hl.dsp.window.resize(fn.resize_active_window(10, 0)), { repeating = true })
hl.bind("SUPER + SHIFT + Minus", hl.dsp.window.resize(fn.resize_active_window(0, -10)), { repeating = true })
hl.bind("SUPER + SHIFT + Equal", hl.dsp.window.resize(fn.resize_active_window(0, 10)), { repeating = true })
hl.bind("SUPER + ALT + left", hl.dsp.window.resize(fn.resize_active_window(-10, 0)), { repeating = true })
hl.bind("SUPER + ALT + right", hl.dsp.window.resize(fn.resize_active_window(10, 0)), { repeating = true })
hl.bind("SUPER + ALT + up", hl.dsp.window.resize(fn.resize_active_window(0, -10)), { repeating = true })
hl.bind("SUPER + ALT + down", hl.dsp.window.resize(fn.resize_active_window(0, 10)), { repeating = true })

hl.bind("SUPER + SHIFT + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + Z", hl.dsp.global("shell:snaplayouts")) -- snap layouts; dragging a window stays on super+shift+mouse above, so kbMoveWindow has no bind left
hl.bind("SUPER + mouse:272", hl.dsp.window.resize(), { mouse = true })
hl.bind(vars.kbResizeWindow, hl.dsp.window.resize(), { mouse = true })
hl.bind("CTRL + SUPER + Backslash", hl.dsp.window.center())
hl.bind("CTRL + SUPER + ALT + Backslash", function()
    hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(55, 70)))
    hl.dispatch(hl.dsp.window.center())
end)
hl.bind(vars.kbWindowPip, function()
    local a = hl.get_active_window()
    if a then
        local pip = fn.move_actions(a) or {}
        if not a.floating then table.insert(pip, 1, hl.dsp.window.float()) end
        table.insert(pip, hl.dsp.window.pin({ action = "on", window = "address:" .. a.address }))

        for _, x in ipairs(pip) do
            hl.dispatch(x)
        end
    end
end)
hl.bind(vars.kbPinWindow, hl.dsp.window.pin())
hl.bind(vars.kbWindowFullscreen, hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(vars.kbWindowBorderedFullscreen, hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(vars.kbToggleWindowFloating, hl.dsp.window.float())
hl.bind(vars.kbCloseWindow, hl.dsp.window.close())
hl.bind("ALT + F4", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/altf4.sh")) -- windows-style: close the window; on the desktop -- the power menu
hl.bind(vars.kbMinimiseWindow, fn.minimise_active) -- the white title-bar button does the same
hl.bind(vars.kbMinimisedWs, fn.toggle_minimised)

-- Special workspace toggles
hl.bind(vars.kbSpecialWs, fn.toggle_special("special"))
hl.bind(vars.kbSystemMonitorWs, fn.toggle_special("sysmon"))
hl.bind(vars.kbMusicWs, fn.toggle_special("music"))
hl.bind(vars.kbCommunicationWs, fn.toggle_special("communication"))
hl.bind(vars.kbTodoWs, fn.toggle_special("todo"))

-- Apps
hl.bind(vars.kbTerminal, function() hl.exec_cmd(vars.terminal) end) -- read at press time: user.lua loads after the binds and can change vars.terminal (back to "kitty -1" included)
hl.bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))
hl.bind(vars.kbEditor, function() if vars.apps.editor then hl.exec_cmd(vars.apps.editor) end end)
hl.bind(vars.kbFileExplorer, hl.dsp.exec_cmd(vars.fileExplorer))
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd(vars.audioSettings))

-- Utilities
hl.bind("Print", hl.dsp.global("shell:shot"))
hl.bind("SUPER + SHIFT + S", hl.dsp.global("shell:shot"))
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/share")) -- clipboard -> LocalSend, Omarchy's key
hl.bind("SUPER + ALT + R", fn.record(false, true))
hl.bind("CTRL + ALT + R", fn.record(false, false))
hl.bind("SUPER + SHIFT + ALT + R", fn.record(true, false))
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))
hl.bind("SUPER + SHIFT + U", hl.dsp.exec_cmd("hyprctl kill"))
-- Volume
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
-- Volume steps: handled by the shell (Sys.stepVol), like brightness -- it unmutes, steps
-- vars.volumeStep up to vars.volumeMax, and ticks. The mute keys above stay wpctl: a toggle,
-- not a level
hl.bind("XF86AudioRaiseVolume", hl.dsp.global("shell:volUp"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.global("shell:volDown"), { locked = true, repeating = true })

-- Sleep
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(vars.sleepGestureCmd), { locked = true })

-- Clipboard
hl.bind("SUPER + V", hl.dsp.global("shell:clip"))
hl.bind("SUPER + Period", hl.dsp.global("shell:charms"))
hl.bind(
    "CTRL + SHIFT + ALT + V",
    hl.dsp.exec_cmd('sleep 0.5s && ydotool type -d 1 "$(cliphist list | head -1 | cliphist decode)"')
    -- no locked: on the lock screen it would type the last copied thing into the password field for anyone at the laptop
)

-- Testing
hl.bind(
    "SUPER + ALT + F12",
    hl.dsp.exec_cmd(
        "notify-send -u low -i dialog-information-symbolic 'Test notification' " ..
        [["Here's a really long message to test truncation and wrapping\nYou can middle click or flick this notification to dismiss it!"]] ..
        " -a 'Shell' -A 'Test1=I got it!' -A 'Test2=Another action'"
    )
)
