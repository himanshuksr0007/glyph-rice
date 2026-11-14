//@ pragma IconTheme Rice
// the shell's icon theme is its own, not qtengine's: if that isn't loaded, Qt
// looks only in hicolor, and apps with generic icon names (kcalc and friends) get empty circles
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "app"
import "bar"
import "buds"
import "cal"
import "charms"
import "clip"
import "deck"
import "desktops"
import "expose"
import "genie"
import "galaga"
import "home"
import "launcher"
import "power"
import "quick"
import "settings"
import "shot"
import "snap"
import "vpn"
import "wall"
import "welcome"
import "services"

// galaga: rice in the spirit of nothing os. Home on the wallpaper, bar, launcher, quick settings,
// Galaga strips at the edges instead of OSD, notification island, power menu, settings, deck (bottom dashboard), clipboard, charms (emoji and symbols), screenshots, vpn, wallpapers. Lock -- a separate process (lock.qml).
// Switches from demonshot via `rice switch` / the Rice app -- hypr keybinds are shared (shell:*), each shell takes its own
ShellRoot {
    id: shell

    Launcher { id: launcher }
    Quick { id: quick; onPowerRequested: power.open(); onSettingsRequested: shell.openSettings() }
    SoundMenu { id: soundMenu; onSettingsRequested: shell.openSettings("sound") }
    BtMenu { id: btMenu; onSettingsRequested: shell.openSettings("bt") }
    WifiMenu { id: wifiMenu; onSettingsRequested: shell.openSettings("wifi") }
    // the settings app loads on first use, not at shell start: it is the
    // biggest object tree in the shell and most sessions never open it. Once
    // loaded it stays loaded -- page memory and open state behave exactly as
    // when it was instantiated eagerly.
    Power { id: power }
    LazyLoader { id: settingsL; Settings { onWallRequested: walls.open(); onVpnRequested: vpn.toggle() } }
    function openSettings(page) { settingsL.active = true; settingsL.item.open(page); }
    function toggleSettings() { settingsL.active = true; settingsL.item.toggle(); }
    Galaga {}
    Buds {}
    Cal { id: cal }
    Clip { id: clip }
    Charms { id: charms }
    Deck { id: deck }
    Desktops { id: desktops }
    Expose { id: expose }
    Genie {}
    Shot { id: shot }
    SnapPop {}
    Vpn { id: vpn }
    LazyLoader { active: !Theme.state.welcomed; Welcome {} } // the first-login card; the features page brings it back
    readonly property bool autoGame: Game.on // starts services/Game: a fullscreen game turns on game mode and dnd
    readonly property bool autoPower: PowerAuto.on // starts services/PowerAuto: battery saver on battery, by itself (settings -> battery)
    // starts services/Sounds (its players preload) and keeps it quiet while a game is fullscreen
    Binding { target: Sounds; property: "gameQuiet"; value: Game.playing }
    Walls { id: walls }

    Variants {
        model: Quickshell.screens
        Scope {
            id: s
            required property var modelData
            Back { screen: s.modelData }
            // bar and home can be taken off a screen (settings -> displays); the wallpaper stays. Here, not in the
            // window: visible from its own screen is a loop (the window is recreated, screen changes)
            Home { screen: s.modelData; visible: Theme.scr(s.modelData.name, "home") }
            Hot { screen: s.modelData; onTriggered: quick.peek() }
            Bar {
                screen: s.modelData
                visible: Theme.scr(s.modelData.name, "bar")
                onMarkClicked: launcher.toggle()
                onTrayClicked: { soundMenu.close(); btMenu.close(); wifiMenu.close(); quick.toggle(); }
                onSoundClicked: { quick.close(); btMenu.close(); wifiMenu.close(); soundMenu.toggle(); }
                onBtClicked: { quick.close(); soundMenu.close(); wifiMenu.close(); btMenu.toggle(); }
                onWifiClicked: { quick.close(); soundMenu.close(); btMenu.close(); wifiMenu.toggle(); }
                onPowerClicked: power.toggle()
                onClockClicked: cal.toggle()
            }
        }
    }

    // hypr like demonshot: its Rules (settings/Rules.qml, the same ~/.config/demonshot/rules.json) sets the monitor, input,
    // motion, night light and hypridle; on top Theme.apply -- its own border colors, rounding and kitty. We call it on theme change too
    Component.onCompleted: {
        hypr();
        if (Theme.state.paint) Theme.apps(); // rice start points the links at term/ -- the colour must be brought back
        Rules.night();
        Rules.idle();
        autoTheme();
        // the hotspot has a password from the very first boot: rolled once,
        // here, and kept until the user changes it -- never re-rolled on use
        if (!Theme.state.hotspotPass) {
            const abc = "abcdefghjkmnpqrstuvwxyz23456789";
            let p = "";
            for (let i = 0; i < 12; i++) p += abc[Math.floor(Math.random() * abc.length)];
            Theme.state.hotspotPass = p;
        }
    }
    // theme auto (settings -> appearance / features): light between lightAt and darkAt (minutes after
    // midnight; lightAt past darkAt reads as an overnight span, equal -- no switch). It
    // applies through Theme.setLight -- the one door every light/dark change uses -- so
    // the schedule picks light/dark WITHIN the colour source STYLE picked (nothing, the
    // wallpaper's tones, or a palette and its pair). A manual flip (settings -> appearance, quick's
    // dark tile) sets themeMode back to 0, and that choice holds until auto is picked
    // again. The 30 s tick also catches up after suspend or a late login: the first
    // tick that sees the wrong side fixes it.
    function autoTheme() {
        if (Theme.state.themeMode !== 1) return;
        const d = new Date(), m = d.getHours() * 60 + d.getMinutes();
        const L = Theme.state.lightAt, D = Theme.state.darkAt;
        const want = L === D ? Theme.state.light : L < D ? (m >= L && m < D) : (m >= L || m < D);
        // through setLight, like every light/dark change: STYLE picks the colour source, this schedule
        // only picks light or dark within it (a palette without a pair keeps its own theme)
        if (want !== Theme.light) Theme.setLight(want);
    }
    Timer { interval: 30000; repeat: true; running: true; onTriggered: shell.autoTheme() }
    // what lives in the hypr config. It re-reads it itself: save any hypr file (the links are live -- both git pull and branch
    // switch), hyprctl reload -- and it returns the variables.lua defaults: demonshot borders, monitor, input, animations. We apply
    // ours again. hyprctl eval does not send configreloaded -- no loop. Night light and hypridle -- their own processes, reload does not touch them
    function hypr() {
        Rules.monitor();
        Rules.input();
        Rules.motion();
        Theme.apply();
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "configreloaded") shell.hypr(); }
    }
    // a screen was plugged in -- its scale and refresh come from settings -> displays (Rules.store.outs)
    Connections {
        target: Quickshell
        function onScreensChanged() { Rules.monitor(true); }
    }
    Connections {
        target: Theme
        function onLightChanged() { paint.restart(); }
        function onGreysChanged() { paint.restart(); }
    }
    // theme or colour changed (style, new wallpaper) -- windows, kitty, gtk and qt. After 300 ms: a new
    // wallpaper's tones do not arrive at once, and gtk should not be nudged twice
    Timer { id: paint; interval: 300; onTriggered: { Theme.apply(); Theme.apps(); } }
    // wallpaper tones (Theme.pick) -- here, not in Theme: the lock loads Theme too and ready-made tones from
    // galaga.json are enough for it. Empty -- the wallpaper copy did not load (greys yield 16 colours): the old
    // tones stay. New wallpaper -- from the first tone
    ColorQuantizer {
        source: Theme.url(Theme.wallSrc(Theme.wall))
        depth: 4
        rescaleSize: 64
        onColorsChanged: {
            if (!colors.length) return;
            const t = Theme.pick(colors);
            if (t.join() === Theme.state.tones.join()) return;
            Theme.state.tones = t;
            Theme.state.paintAt = 0;
        }
    }
    Connections {
        target: Theme.state
        function onRoundingChanged() { Theme.apply(); }
        function onThemeModeChanged() { shell.autoTheme(); }
        function onLightAtChanged() { shell.autoTheme(); }
        function onDarkAtChanged() { shell.autoTheme(); }
    }
    // ultra mode enables/disables blur and shadows on top of the settings -- repaint windows (refresh rate and motion are set by Rules.setMode itself).
    // Game -- the same plus animations
    Connections {
        target: Rules.store
        function onUltraChanged() { Theme.apply(); }
        function onGameChanged() { Rules.motion(); Theme.apply(); }
    }

    // tap Super -- launcher. Super+<key> swallows and decides when to open, hyprland/keybinds.lua (key polling):
    // the global only gives pressed, without released, so the release is handled on the hypr side
    Shortcut {
        name: "launcher"
        description: "launcher (tap Super)"
        onPressed: launcher.toggle()
    }
    // Super+Space (altar in demonshot) -- deck, bottom dashboard: the launcher is already on tapping Super
    Shortcut { name: "altar"; description: "deck: bottom dashboard"; onPressed: deck.toggle() }
    Shortcut { name: "desktops"; description: "desktops overview"; onPressed: desktops.toggle() }
    Shortcut { name: "expose"; description: "exposé: windows on this desktop"; onPressed: { if (Theme.state.featExpose) expose.toggle(); } }
    Shortcut { name: "quick"; description: "quick settings"; onPressed: quick.toggle() }
    Shortcut { name: "ward"; description: "quick settings"; onPressed: quick.toggle() } // Super+N in demonshot -- same toggles
    Shortcut { name: "settings"; description: "settings"; onPressed: shell.toggleSettings() }
    Shortcut { name: "snapleft"; description: "snap window left"; onPressed: Snap.snapDir("left") }
    Shortcut { name: "snapright"; description: "snap window right"; onPressed: Snap.snapDir("right") }
    Shortcut { name: "snapup"; description: "snap window up"; onPressed: Snap.snapDir("up") }
    Shortcut { name: "snapdown"; description: "snap window down"; onPressed: Snap.snapDir("down") }
    Shortcut { name: "snaplayouts"; description: "snap layouts"; onPressed: Snap.toggleLayouts() }
    Shortcut { name: "power"; description: "power menu"; onPressed: power.toggle() }
    Shortcut { name: "shot"; description: "screenshot"; onPressed: shot.open() }
    Shortcut { name: "pact"; description: "vpn: clash verge"; onPressed: vpn.toggle() }
    Shortcut { name: "clip"; description: "clipboard"; onPressed: clip.toggle() }
    Shortcut { name: "charms"; description: "emoji, kaomoji, symbols"; onPressed: charms.toggle() }
    Shortcut { name: "wall"; description: "wallpapers"; onPressed: walls.toggle() }
    Shortcut { name: "game"; description: "game mode"; onPressed: Rules.store.game = !Rules.store.game }

    component Shortcut: GlobalShortcut { appid: "shell" }
}
