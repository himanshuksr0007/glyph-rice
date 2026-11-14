pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.settings
import "schemes.js" as Schemes

// galaga: black, white dots, one red. Palette, fonts, motion, state (theme, do-not-disturb) and the look of hypr/kitty -- all here
Singleton {
    id: root

    // state survives a restart, and the lock reads it too (separate process)
    readonly property alias state: st
    // colour -- where from (launcher -> style, settings -> STYLE), like scheme in caelestia: nothing -- black, white
    // and red; wall -- from the wallpaper's tone by variant, like dynamic in caelestia (tonal spot, fruit salad... --
    // schemes.js); scheme -- a ready palette, the theme is its own. A palette is { light, c: the greys by the roles
    // below, accent, red, ansi: kitty's 16 colours }
    readonly property var palBase: make({})
    // your own colours (settings -> appearance — click a colour well): st.custom sits on top of whatever
    // palette is live. Keys: bg s1 s2 s3 mute grey fg accent red, and a0..a15 for the terminal
    // colours. Everything reads pal -- the shell, kitty (apply), gtk/qt/tmux/firefox (apps) --
    // so a custom colour follows the whole system until it is reset
    readonly property var pal: {
        const cu = st.custom, b = palBase;
        if (!cu || !Object.keys(cu).length) return b;
        const cc = b.c.slice(), an = b.ansi.slice();
        ["bg", "s1", "s2", "s3", "mute", "grey", "fg"].forEach((r, i) => { if (cu[r]) cc[i] = cu[r]; });
        for (let i = 0; i < 16; i++) if (cu["a" + i]) an[i] = cu["a" + i];
        const o = Object.assign({}, b, { c: cc, ansi: an });
        if (cu.accent) o.accent = cu.accent;
        if (cu.red) o.red = cu.red;
        return o;
    }
    readonly property bool light: pal.light
    // set (a "#hex" string) or clear (null) one custom colour
    function setCustom(key, hex) {
        const cu = Object.assign({}, st.custom);
        if (hex) cu[key] = hex; else delete cu[key];
        st.custom = cu;
    }

    // light theme -- same layout, greys inverted; red does not change
    readonly property var galagaDark: ["#000000", "#0E0E0E", "#1A1A1A", "#2A2A2A", "#4A4A4A", "#8C8C8C", "#F2F2F2"]
    readonly property var galagaLight: ["#E9E9E9", "#FFFFFF", "#F1F1F1", "#D9D9D9", "#B8B8B8", "#6E6E6E", "#0B0B0B"]
    readonly property var greys: pal.c
    readonly property color bg: greys[0]   // background, wallpapers
    readonly property color s1: greys[1]   // bar, panels
    readonly property color s2: greys[2]   // tiles, off
    readonly property color s3: greys[3]   // lines, dimmed dots
    readonly property color mute: greys[4] // inactive
    readonly property color grey: greys[5] // labels, secondary
    readonly property color fg: greys[6]   // text, on, focus
    readonly property color ink: light ? s1 : bg // text on a white tile
    readonly property color accent: pal.accent // at most one thing on screen, and only "live"
    readonly property color red: pal.red       // alarm: battery, critical, wrong password
    readonly property color nothingRed: "#D71921"
    readonly property color glow: light ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color scrim: fade(bg, light ? 0.8 : 0.74)

    readonly property string dot: "Doto"                   // digits and short words, not smaller than 26px
    readonly property string ui: "Space Grotesk"
    readonly property string mono: "Space Mono"            // labels in caps
    readonly property string nf: "JetBrainsMono Nerd Font" // icons

    // 1920x1080 layout canvas -> screen. ponytail: based on the first screen; on a second screen the layout is the same
    // (hypr's scale does the sizing), only the home bento hugs the right edge there
    readonly property real s: {
        const sc = Quickshell.screens[0];
        if (!sc) return 1;
        // orientation-agnostic (SenulMapa's fix): a portrait first screen made this 0.5625 and shrank everything
        const long = Math.max(sc.width, sc.height), short = Math.min(sc.width, sc.height);
        return Math.min(long / 1920, short / 1080);
    }

    // a screen's own settings live in state.screens under the monitor's MODEL: it is the monitor, not the port --
    // the same monitor through another port or a dock keeps its own. Two identical monitors, or one without a
    // model, go by port name. The model is the same one hyprctl reports (Rules.key)
    function sid(name) {
        const m = Quickshell.screens.find(s => s.name === name)?.model.trim();
        return m && Quickshell.screens.filter(s => s.model.trim() === m).length === 1 ? m : name;
    }
    // by name -- an old entry (from before models) or a twin that is currently alone
    function own(name) { return st.screens[sid(name)] ?? st.screens[name]; }
    // a screen's setting by output name: its own, else the shared one; bar and home default to on
    function scr(name, key) { return own(name)?.[key] ?? { wall: st.wall, widgets: st.widgets }[key] ?? true; }
    // undefined -- drop the screen's own value, it takes the shared one. An entry under a port name is copied under
    // the model but stays: if a twin appears, that screen is looked up by port again
    function setScr(name, key, v) {
        const o = Object.assign({}, own(name)), all = Object.assign({}, st.screens);
        if (v === undefined) delete o[key];
        else o[key] = v;
        all[sid(name)] = o;
        st.screens = all;
    }
    // the first screen's wallpaper, its own or the shared one -- the colour source reads this one
    readonly property string wall: scr(Quickshell.screens[0]?.name, "wall")

    // ---- wallpaper tones: up to four to choose from, like android's. They live in galaga.json: the lock (a separate
    // process) takes them ready-made and does not flash red ----
    readonly property var tones: wall ? st.tones : []
    function hueName(c) {
        const h = Qt.color(c).hslHue * 360;
        return ["red", "orange", "yellow", "green", "teal", "blue", "violet", "pink", "red"][[15, 40, 65, 160, 195, 250, 290, 335, 361].findIndex(x => h < x)];
    }
    // the palette as it would be with st plus the overrides o ({ paint, scheme, at, variant, light }): the shell lives
    // by it (o empty), the STYLE samples show it too. No tones (grey wallpaper, no picture) -- nothing
    function make(o) {
        const k = Object.assign({ paint: st.paint, scheme: st.scheme, at: st.paintAt, variant: st.variant, light: st.light }, o);
        if (k.paint === "scheme") return Schemes.ALL.find(p => p.id === k.scheme) ?? Schemes.ALL[0];
        // galaga's 16 ANSI: in light 0<->15 and 7<->8 swapped, so white is not lost on white
        const base = { light: k.light, c: k.light ? galagaLight : galagaDark, accent: nothingRed, red: nothingRed,
                       ansi: k.light ? [15, 1, 2, 3, 4, 5, 6, 8, 7, 9, 10, 11, 12, 13, 14, 0].map(i => ansi[i]) : ansi };
        const src = tones[Math.min(k.at, tones.length - 1)];
        return k.paint === "wall" && src ? Schemes.dynamic(src, k.variant, base) : base;
    }
    // theme: a palette's own, or its pair from the same group (mocha -> latte, dawn -> main); no pair (nord, dracula...)
    // -- the theme does not change, or st.light would diverge from the screen and surface at a source switch.
    // setLight is the ONE door for light/dark: the appearance toggle, quick's dark tile and the theme-Auto schedule
    // (shell.qml) all go through it, so the schedule applies within whatever source STYLE picked
    function pair(l) { return st.paint !== "scheme" ? null : pal.light === l ? pal : Schemes.ALL.find(x => x.group === pal.group && x.light === l) ?? null; }
    function setLight(l) {
        const p = pair(l);
        if (st.paint === "scheme" && !p) return;
        if (p) st.scheme = p.id;
        st.light = l;
    }
    // the choice for the launcher (style) and settings (STYLE): blocks { head, items: [{ name, pal, fill, dot, now, run }] };
    // pal -- the palette if picked, fill -- the swatch circle, dot -- the smaller circle in it (the accent), now -- currently set.
    // First where the colour is from, under it -- what that source has: wallpaper tones and variants, or palettes by group;
    // at the end the theme
    readonly property var styles: {
        const set = (k, v) => () => st[k] = v, at = Math.min(st.paintAt, tones.length - 1);
        const it = (name, p, now, run, fill) => ({ name, pal: p, fill: fill ?? p.c[1], dot: p.accent, now, run });
        const own = st.paint === "wall" ? [
            { head: "tones", items: tones.map((t, i) => it(hueName(t), make({ at: i }), at === i, set("paintAt", i), t)) },
            // the circle is the variant's mute grey (you see where the greys went), the accent inside it; amount -- the share of colour, in order
            { head: "variant", items: tones.length ? Schemes.VARIANTS.map((v, i) => {
                const p = make({ variant: v.id });
                return Object.assign(it(v.name, p, st.variant === v.id, set("variant", v.id), p.c[4]), { amount: i / (Schemes.VARIANTS.length - 1) });
            }) : [] }
        ] : st.paint === "scheme" ? Schemes.GROUPS.map(g => ({ head: g, items: Schemes.ALL.filter(p => p.group === g).map(p =>
            Object.assign(it(p.name, p, st.scheme === p.id, () => { st.scheme = p.id; st.light = p.light; }), { extra: g })) })) : [];
        return [{ head: "source", items: [
            it("nothing", make({ paint: "" }), !st.paint || st.paint === "wall" && !tones.length, set("paint", ""), nothingRed),
            it("wallpaper", make({ paint: "wall" }), st.paint === "wall" && !!tones.length, set("paint", "wall"), tones[0]),
            it("palette", make({ paint: "scheme" }), st.paint === "scheme", set("paint", "scheme"))
        ] }].concat(own.filter(b => b.items.length), [
            { head: "theme", items: [["dark", false], ["light", true]].map(([n, l]) => it(n, make({ light: l, scheme: pair(l)?.id ?? st.scheme }),
                light === l, () => setLight(l))) }
        ]);
    }
    // like material-you's score, only simpler: the quantizer cuts the picture into 16 equal-area pieces and returns each
    // piece's average colour. The juicy vote (chroma -- max-min of channels -- above 0.12; below it big pale fills win, not
    // the picture's colour): the hue there is most of (±15°) leads, among its own -- the juiciest. Then up to three more,
    // no closer than 30° to each other. None juicy -- no tones, red stays. Called by the quantizer in shell.qml (not here:
    // Theme is loaded by the lock too)
    function pick(cols) {
        const ch = c => c.hsvSaturation * c.hsvValue, d = (a, b) => Math.abs((a.hsvHue - b.hsvHue + 1.5) % 1 - 0.5);
        const all = Array.from(cols), live = all.filter(c => ch(c) > 0.12);
        const score = c => 0.7 * live.filter(o => d(o, c) < 1 / 24).length / all.length + 0.3 * ch(c);
        const out = [];
        for (const c of live.sort((a, b) => score(b) - score(a)))
            if (out.length < 4 && out.every(o => d(o, c) >= 1 / 12)) out.push(c);
        return out.map(c => c.toString());
    }
    // relative luminance, as in WCAG
    function lum(c) { c = Qt.lighter(c, 1); const f = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b); }
    // what to write over colour c: black or white, whichever contrasts more (luminance threshold 0.18 -- per WCAG)
    function on(c) { return lum(c) > 0.18 ? "#000000" : "#FFFFFF"; }

    // glide: ease-out-quart, no overshoot -- like the bezier glide in hypr
    readonly property var glide: [0.25, 1, 0.5, 1, 1, 1]
    readonly property int t: 350

    // ---- shell performance (state.perf): the shell's own recurring costs, derived from the one key,
    // so a level change re-binds live everywhere and a restart just re-reads the key ----
    // lite: the eye-candy consumers stand down (cava's two registrations, the RunCat, the spinning
    // covers, the orb's breathing) -- consumers multiply by !perfLite, nothing here touches Rules
    readonly property bool perfLite: st.perf === 2
    // polling cadences, ms: full as shipped, trim half rate, lite quarter rate
    readonly property int statsMs: [2000, 4000, 8000][st.perf] ?? 2000   // SysStats sampling (home, deck, the cat's cpu)
    readonly property int sysPollMs: [3000, 6000, 12000][st.perf] ?? 3000 // Sys: the recording / airplane-mode check (a process spawn)
    readonly property int ddcMs: [5000, 10000, 20000][st.perf] ?? 5000   // Backlight: the external monitor's DDC read-back (a ~300 ms ddcutil call)

    // wallpapers are drawn from a copy sized for the screen (the picker makes it, magick): the original can be a 40 MB png and would take seconds to load.
    // ponytail: no copy (cache wiped, path typed by hand) -- empty, grid and orb, until the picker is opened
    readonly property string wallCache: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/galaga/walls"
    function wallSrc(p) { return p ? `${wallCache}/${p.slice(p.lastIndexOf("/") + 1)}.jpg` : ""; }
    function url(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : ""; }

    function fade(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    // a panel's, tile's, pill's corner radius -- by the corners setting (settings -> windows -> panels): 0 straight, 100 as designed
    function corner(px) { return px * st.corners / 100; }
    // clock per 12/24 setting: "09" or "9"
    function hh(d) { const h = d.getHours(); return st.clock24 ? String(h).padStart(2, "0") : String(h % 12 || 12); }
    function hex(c) { return c.toString().slice(1, 7).toUpperCase(); }

    readonly property string riceState: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice"
    // as in Rules: apply() at startup must see galaga.json, not the defaults
    Component.onCompleted: stateFile.waitForJob()

    FileView {
        id: stateFile
        path: root.riceState + "/galaga.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        // write -- once at the end of the turn: writeAdapter() on every field in a row mixes up neighbors
        onAdapterUpdated: Qt.callLater(stateFile.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: st
            property bool light: false
            property string paint: ""     // where colour is from: empty -- nothing, wall -- the wallpaper, scheme -- a palette
            property string scheme: "mocha" // which palette, an id from schemes.js
            property int paintAt: 0       // which of the wallpaper tones
            property var tones: []        // the wallpaper tones, written by the quantizer; empty -- grey wallpaper or no picture
            property string variant: "tonalspot" // how a wallpaper tone becomes a palette, an id from schemes.js (VARIANTS)
            property var custom: ({})      // your own colours over the palette (settings -> appearance): role -> "#hex"; empty -- the palette as designed
            property bool dnd: false  // new ones are not shown, critical ones always
            property int unread: 0    // for the lock
            property bool welcomed: false // the first-login card was dismissed (welcome/Welcome.qml)
            // ---- what the settings app changes ----
            property var widgets: ["weather", "calendar", "cpu", "player", "buds", "system"] // home bento in order, see kinds
            property bool homeClock: true  // home shows the clock and date (settings -> appearance -> home screen)
            property bool homeHello: true  // ... the greeting and the line under it
            property bool homeBento: true  // ... the widgets
            property bool clock24: true
            property bool blink: true      // clock colon blinks
            property string name: ""       // in the greeting; empty -- $USER
            property bool grid: true       // dot grid on the wallpaper
            property bool orb: true        // halftone orb
            // wallpaper (picker wall/Walls, drawn by components/Wall): path to the image; empty -- grid and orb. The picker folder can be changed here
            property string wall: ""
            property string wallDir: ""    // empty -- ~/Pictures/Wallpapers
            property int wallLook: 0       // 0 dots, 1 grey photo, 2 color, 3 vivid dots (the pixel's own colour)
            property int wallPitch: 10     // dot pitch, px
            property int wallBright: 85
            property string gif: ""       // the cat tile's gif (services/Gifs), a path; empty -- the first in the folder
            property string gifDir: ""    // empty -- ~/Pictures/Gifs    // %, from background to image
            property int rounding: 20      // hypr windows
            property int corners: 100      // the shell panels' corners, % of their own; round things stay round (Theme.corner)
            property bool edges: true      // Galaga strips at the edges (volume/brightness, flashes, progress)
            property int briSteps: 20      // brightness from the keys: divisions per scale, 40/20/10 -- step 2.5/5/10 %
            property bool quickHover: true // quick settings on hover at the right edge
            property bool deckHover: true  // deck -- bottom-center panel, slides out on hovering the edge
            property bool genie: true      // minimise warps the window into the deck's minimised section (genie/Genie.qml); off -- a plain park
            // ---- the feature programme: one persisted toggle per feature (settings -> features). Off -- the feature is fully inert ----
            property bool featGenieBack: true  // restore expands the park-time snapshot back out of the minimised section (genie/Genie.qml)
            property bool featEdges: true      // reactive galaga edges: music VU, charging fill, focus drain (galaga/Galaga.qml)
            property bool featExpose: true     // all-windows exposé of the current desktop (expose/Expose.qml)
            property bool featLockMedia: true  // media controls + notification summary on the session lock (lock/LockFace.qml)
            property bool featEssential: false // essential notifications: only the picked apps light the edges (Notes.qml); off by default -- it changes notification behaviour
            property var essentialApps: []     // desktop entry ids picked in settings -> notifications
            property var peek: []              // latest notifications [{ app, summary }] -- written by Notes, read by the lock face
            property bool featLauncher: true   // launcher smarts in apps mode: maths, conversions, kill, files (launcher/Launcher.qml)
            property bool featFocus: true      // focus timer as a bar tray widget (bar/Bar.qml); the timer itself also lives in cal/Cal.qml
            property int themeMode: 0          // 0 -- manual (the light field above decides), 1 -- auto on the schedule below
            property int lightAt: 420          // auto: light from 07:00 -- minutes after midnight, edited in settings -> appearance
            property int darkAt: 1140          // auto: dark from 19:00
            property bool featDesktops: true   // per-desktop names + wallpapers (settings -> desktop & deck)
            property var wsNames: ({})         // desktop id (as string) -> name; missing -- just the number
            property var wsWalls: ({})         // desktop id (as string) -> wallpaper path; missing/"" -- the global wall above
            property bool featShot: true       // shot: grab text (OCR) and scan QR modes (shot/Shot.qml)
            property bool featGameAuto: true   // a fullscreen game turns on game mode (+ dnd) by itself (services/Game.qml)
            property bool snap: true       // windows-style snapping (services/Snap): super+arrows snap, super+z opens the layouts
            property bool snapLinked: true // snapped neighbours resize together: drag one window's edge, the next one follows
            property bool snapAssist: true // after a snap, offer the other windows to fill the rest of the space
            property bool snapDrag: true   // drag a window to an edge or corner and let go to snap it there
            property int perf: 0           // shell performance (settings -> battery): 0 full, 1 trim, 2 lite -- what the shell itself spends: polling cadences and ambient motion. The cpu profile is Rules.modes, not this
            property bool sounds: true         // interface sounds (services/Sounds): quiet synthesized blips -- lock, shots, notes, ticks
            property int soundVol: 55          // their volume, %
            property bool soundUi: true        // interface: panels opening (pop), the volume tick
            property bool soundAlerts: true    // alerts: a notification arriving
            property bool soundSys: true       // system: lock, unlock, screenshot, charger
            property var gameAuto: null        // services/Game: what game mode and dnd were before it took them; null -- it isn't holding them
            property var powerHold: null       // services/PowerAuto: { mode } to restore when the charger returns; null -- it isn't holding one
            property string avatar: ""         // profile photo: the copy in the state dir; "" -- the dotted face (lock/LockFace.qml)
            property bool lockHideLen: false // lock: three fixed dots while typing, the password's length doesn't show (SenulMapa's idea, AMM021's port)
            property bool lockOneScreen: false // lock: the full face only on the screen in focus, the others get a plain cover
            property string lockWall: ""     // the lock's own wallpaper: the copy in the state dir; "" -- the desktop wallpaper (settings -> lock)
            property int lockClock: 0        // the lock's clock: 0 matrix, 1 stacked, 2 analogue (settings -> lock)
            property var deck: ["clock", "weather", "perf", "net", "media", "min"] // its sections in order, see decks
            property var bar: ["layout", "wifi", "bluetooth", "sound", "notes", "focus", "battery", "mode", "power"] // bar tray from top to bottom, see bars
            property bool barTitle: true   // window title stacked in the bar
            property string barAt: "left"  // left or top; the calendar, the battery card, home, the island and the Galaga flash follow the bar
            // recording (quick/Rec, Sys.recArgs)
            property int recArea: 0        // 0 whole monitor, 1 region (slurp)
            property int recAudio: 0       // 0 no sound, 1 system, 2 microphone, 3 both on one track
            property int recFps: 60
            property int recQuality: 2     // medium, high, very_high, ultra
            property bool recCursor: true
            property bool vpnPortal: false // tunnel taken down for a captive portal, restore it in the open (vpn/Vpn)
            property bool audioMeter: false // AUDIO page level meter: PwNodePeakMonitor crashes quickshell 0.3.0, so it is opt-in for 0.3.1+
            property bool featEq: true       // system eq (services/Eq): a pipewire filter chain in front of a device, gains per device in eqDev
            property var eqDev: ({})          // sink node name -> { on, lo, mid, hi } (decibels); missing -- off and flat
            property string hotspotSsid: ""   // personal hotspot name (quick/WifiMenu); empty -- the machine's hostname
            property string hotspotPass: ""   // personal hotspot password; empty -- one is made when the hotspot first starts
            property var screens: ({})     // per-screen own settings by monitor model (Theme.sid): { bar, home, widgets, wall }
        }
    }

    // bento widgets: id -> width in cells (3-column x 3-row grid, 220 each). Does not fit -- not shown
    readonly property var kinds: ({ weather: 1, calendar: 1, cpu: 1, ram: 1, gpu: 1, disk: 1, battery: 1, buds: 1, player: 2, system: 3, cat: 1, cava: 1 })
    // deck sections
    readonly property var decks: ["clock", "weather", "perf", "net", "media", "min"]
    // bar tray
    readonly property var bars: ["layout", "wifi", "bluetooth", "sound", "notes", "focus", "battery", "mode", "power", "cat"]

    // ---- the look of everything outside the shell. Called only by shell.qml: at startup and on theme change ----
    // hypr inherits from demonshot: monitor, input, idle, night light and motion are set by its Rules (shell.qml), animations -- from the
    // hypr config. From here -- gaps/border/blur/shadows from its rules.json, while galaga's own -- border colors, shadows, groups, background and
    // rounding 20 (without them the red glow and demonshot groups from hypr/variables.lua would remain).
    // Back to demonshot: `rice switch` runs hyprctl reload, its applyAll repaints
    function hypr(lua) { Quickshell.execDetached(["hyprctl", "eval", lua]); }

    // kitty includes this file after its own colors (include in kitty.conf); demonshot writes its palette there too
    FileView { id: kitty; path: Quickshell.env("HOME") + "/.config/demonshot/kitty.conf"; printErrors: false }
    // 16 ANSI from the concept: pastel only for the terminal. In the light theme 0<->15 and 7<->8, so white is not lost on white
    readonly property var ansi: ["#0E0E0E", "#D71921", "#9BB59A", "#D9C38A", "#8EA3C2", "#B79BC2", "#8FB8B8", "#C9C9C9",
                                 "#4A4A4A", "#F0434B", "#B5CCB4", "#E8D6A8", "#AABBD4", "#CDB6D6", "#ABCDCD", "#F2F2F2"]

    function apply() {
        // game mode (Rules.store.game) -- on top of the settings, like ultra: border 1, no gaps or rounding, tearing for
        // windows with immediate (games, hyprland/rules.lua). Exit -- your values return, allow_tearing -- false, as in general.lua
        const r = Rules.store, g = r.game, flat = g && !r.gameGaps; // flat -- game mode without "keep gaps"
        const c = x => `"rgb(${hex(x)})"`;
        // shadow: in dark -- a barely visible white glow, in light -- a soft black
        const shadow = light ? "rgba(0000002E)" : `rgba(${hex(fg)}1A)`;
        hypr(`hl.config({ general = { gaps_in = ${flat ? 0 : r.gapsIn}, gaps_out = ${flat ? 0 : r.gapsOut}, border_size = ${flat ? 1 : r.border}, allow_tearing = ${g}, `
           + `col = { active_border = ${c(fg)}, inactive_border = ${c(s3)} } }, `
           + `decoration = { rounding = ${flat ? 0 : st.rounding}, blur = { enabled = ${Rules.blurOn} }, shadow = { enabled = ${Rules.shadowOn}, color = "${shadow}" } }, `
           + `group = { col = { border_active = ${c(fg)}, border_inactive = ${c(s3)}, border_locked_active = ${c(fg)}, border_locked_inactive = ${c(mute)} }, `
           + `groupbar = { font_family = "${mono}", text_color = ${c(fg)}, col = { active = ${c(s3)}, inactive = ${c(s1)}, locked_active = ${c(s3)}, locked_inactive = ${c(s1)} } } }, `
           + `misc = { background_color = ${c(bg)} } })`);

        kitty.setText("# galaga: written by Theme.apply(), do not edit by hand\n" + [
            ["font_family", "Space Mono"], ["window_padding_width", "26 30"], ["cursor_trail", "0"],
            ["foreground", fg], ["background", s1], ["cursor", fg], ["cursor_text_color", s1],
            ["selection_foreground", fg], ["selection_background", s3], ["url_color", grey],
            ["active_border_color", fg], ["inactive_border_color", s3],
            ["active_tab_foreground", ink], ["active_tab_background", fg],
            ["inactive_tab_foreground", grey], ["inactive_tab_background", s1], ["tab_bar_background", bg]
        ].concat(pal.ansi.map((c, i) => ["color" + i, c])).map(([k, v]) => `${k} ${typeof v === "string" ? v : v.toString().slice(0, 7).toUpperCase()}`).join("\n") + "\n");
        Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"]);
    }

    // gtk and qt -- only on a colour change (shell.qml): apply() is also called on every rounding-ring step. The templates
    // are our own term/ (galaga's dark palette): their colours are swapped for the same roles' colours in the palette (the
    // greys, red, for qt also green/yellow/blue... from ansi), copies go to riceState/galaga, the ~/.config/... links are
    // pointed at the copies. Nothing to change -- back to term/, as rice sets it. A real file (not a link) is not touched,
    // like rice. The swap runs in two passes through @n@: a palette colour can coincide with a glyph colour replaced later.
    // gtk and qt take the colours at the next app start: gtk reads its gtk.css once, nudging the theme does not help
    // (checked on gtk 3 and 4).
    // ponytail: the light theme here is dark -- the gtk base is dark (adw-gtk3-dark): for wallpapers -- the same variant in
    // dark, for palettes -- the dark pair (latte -> mocha), for nothing -- galaga; a light one would need the gtk-theme and
    // color-scheme changed too. btop is not painted -- its folder is linked whole into the repo, nowhere to put a copy;
    // if needed -- a color_theme path to a copy
    function apps() {
        const from = galagaDark.concat(ansi.slice(1, 7));
        const p = pal.light ? pair(false) ?? make({ light: false }) : pal;
        const to = p.c.concat([p.red], p.ansi.slice(2, 7));
        const pairs = from.map((c, i) => [c, "#" + hex(Qt.lighter(to[i], 1))]).filter(([a, b]) => a !== b);
        const sed = pairs.map(([a], i) => ["-e", `s/${a}/@${i}@/gI`]).concat(pairs.map(([, b], i) => ["-e", `s/@${i}@/${b}/g`])).reduce((x, y) => x.concat(y), []);
        Quickshell.execDetached(["bash", "-c", `t=$1 o=$2; shift 2
for f in gtk-3.0/gtk.css gtk-4.0/gtk.css qtengine.colors; do
    l=$HOME/.config/$f
    [ -L "$l" ] || [ ! -e "$l" ] || continue
    if [ $# -gt 0 ]; then mkdir -p "$(dirname "$o/$f")" && sed "$@" "$t/$f" > "$o/$f" && ln -sfn "$o/$f" "$l"; else ln -sfn "$t/$f" "$l"; fi
done
# our gtk.css paints the window discs from window-buttons/ next to itself: in a recoloured copy that folder must
# resolve too, or the hover glyphs vanish under any non-nothing palette
if [ $# -gt 0 ]; then for d in gtk-3.0 gtk-4.0; do ln -sfn "$t/window-buttons" "$o/$d/window-buttons"; done; fi`,
            "bash", Quickshell.shellPath("term"), riceState + "/galaga"].concat(sed));
        tmux();
        fox();
        vesk(p);
    }

    // tmux follows the palette too (Isaqdn03's idea, AMM021's form): theme.conf carries the whole status
    // styling, tmux.conf sources it (the installer adds that line), running servers re-read it live.
    function tmux() {
            const accent = hex(pal.accent), conf = `# galaga: written by Theme.apps(), don't edit by hand
    set -g status-style "bg=#${hex(s1)},fg=#${hex(grey)}"
    set -g status-left-style "fg=#${accent}"
    set -g window-status-current-style "fg=#${hex(fg)},bold"
    set -g pane-border-style "fg=#${hex(s3)}"
    set -g pane-active-border-style "fg=#${accent}"
    set -g message-style "bg=#${hex(s2)},fg=#${hex(fg)}"
    set -g mode-style "bg=#${hex(s3)},fg=#${hex(fg)}"
    setw -g clock-mode-colour "#${accent}"
    `;
            Quickshell.execDetached(["sh", "-c", 'command -v tmux >/dev/null || exit 0; d=$HOME/.config/tmux; mkdir -p "$d" && printf "%s" "$1" > "$d/theme.conf"; '
                + 'tmux source-file -q "$d/theme.conf" 2>/dev/null; tmux refresh-client -S 2>/dev/null; true', "sh", conf]);
    }

    // Firefox through Pywalfox (AUR python-pywalfox + its add-on), which themes the browser live from pywal's colors.json. Its default template
    // reads a few slots: dark — frame 0, toolbar and field are 0 lightened, text 15, icons and highlight pills 10, attention 13; light — frame 7, toolbar
    // white, text 0, icons 3, attention 5. Frame is s1 like the bar, icons and pills fg, the accent only what wants attention. Firefox closed — pywalfox
    // can't connect, quietly. Not installed — nothing is written. The AUR package registers the native host in /usr/lib/mozilla: never `pywalfox install`
    // as the user, it makes ~/.mozilla and that sends Firefox back to a fresh, empty profile. From Isaqdn03/glyph-rice
    function fox() {
        const h = c => "#" + hex(c), a = pal.ansi.map(h), [bg, s1, , , , , fg] = greys;
        Object.assign(a, pal.light ? { 0: h(fg), 3: h(fg), 5: h(pal.accent), 7: h(bg) } : { 0: h(s1), 10: h(fg), 13: h(pal.accent), 15: h(fg) });
        const colors = {};
        a.forEach((c, i) => colors["color" + i] = c);
        const json = JSON.stringify({ wallpaper: st.wall, alpha: "100", special: { background: h(bg), foreground: h(fg), cursor: h(fg) }, colors }, null, 2);
        Quickshell.execDetached(["sh", "-c", `command -v pywalfox >/dev/null || exit 0
mkdir -p "$1" && printf '%s\\n' "$2" > "$1/colors.json.tmp" && mv -f "$1/colors.json.tmp" "$1/colors.json" || exit
{ pywalfox "$3"; pywalfox update; } >/dev/null 2>&1; true`,
            "sh", (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/wal", json, pal.light ? "light" : "dark"]);
    }

    // Vesktop's "rice" theme = term/vesktop.css (Galaga on top of midnight) + this palette's --g-* in a :root after it,
    // so they win. The dark pair, as gtk: Discord's own dark theme sits underneath. Vencord watches themes/ and reloads live.
    // No ~/.config/vesktop — Vesktop isn't used, nothing to write
    function vesk(p) {
        const h = c => "#" + hex(Qt.lighter(c, 1)), c = p.c;
        const vars = [["bg", c[0]], ["s1", c[1]], ["s2", c[2]], ["s3", c[3]], ["mute", c[4]], ["grey", c[5]], ["fg", c[6]], ["ink", c[0]],
                      ["accent", p.accent], ["red", p.red], ["on-red", on(p.red)], ["yellow", p.ansi[3]]];
        const css = `\n/* Theme.apps(): the palette now */\n:root {\n${vars.map(([k, v]) => `    --g-${k}: ${h(v)};`).join("\n")}\n}\n`;
        Quickshell.execDetached(["sh", "-c", `[ -d "$HOME/.config/vesktop" ] || exit 0
d=$HOME/.config/vesktop/themes
mkdir -p "$d" && { cat "$1" && printf '%s' "$2"; } > "$d/.rice.tmp" && mv -f "$d/.rice.tmp" "$d/rice.theme.css"`,
            "sh", Quickshell.shellPath("term/vesktop.css"), css]);
    }
}
