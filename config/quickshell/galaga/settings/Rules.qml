pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// house rules: ~/.config/demonshot/rules.json -- the single source of truth for settings.
// Editing from Settings writes the file (writeAdapter) and calls the needed apply itself. applyAll is called only by shell.qml at startup:
// the lock (lock.qml) also reads Theme -> Rules, but applies nothing
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/demonshot"
    readonly property alias store: adapter

    // eight colors in Theme order: void crypt wine plum rose crimson ash bone
    readonly property var palettes: [
        { name: "Demon's Shot", what: "blood & bone", c: ["#0D0B0E", "#151116", "#2B1820", "#4A2236", "#B8487A", "#C7303D", "#7A6870", "#E9DFDD"] },
        { name: "Absinthe", what: "green fairy", c: ["#0B0D0B", "#121612", "#1E2A1F", "#2F4630", "#A9B85A", "#7CC24A", "#6E7A6C", "#E3E6D8"] },
        { name: "Nightshade", what: "poison bloom", c: ["#0C0B10", "#131119", "#221A30", "#3A2852", "#8E6BD8", "#B04BD6", "#706A80", "#E4DFEA"] },
        { name: "Holy Water", what: "cold blessing", c: ["#0A0C10", "#11151B", "#1A2433", "#263C57", "#5E9BD1", "#3F7FE0", "#687687", "#DDE4EA"] },
        { name: "Rust", what: "old iron", c: ["#0E0B09", "#17120F", "#2E1D14", "#4D2E1C", "#D08A3E", "#D1532A", "#7E6E62", "#EADFD3"] },
        { name: "Gilded", what: "altar gold", c: ["#0D0C0A", "#16140F", "#2E2716", "#4A3D1E", "#B88A4A", "#D9A43A", "#7A7262", "#EDE5D3"] },
        { name: "Ghost", what: "no color left", c: ["#0C0C0D", "#141416", "#26262A", "#3A3A40", "#9A9AA6", "#E9E9EE", "#6E6E76", "#E2E2E6"] }
    ]
    readonly property var pal: palettes[adapter.palette] ?? palettes[0]

    // wait for the file when the singleton is created: otherwise the first one to read store (galaga at startup) gets the defaults, not rules.json
    Component.onCompleted: file.waitForJob()

    FileView {
        id: file
        path: root.dir + "/rules.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: this.reload()
        // write -- once at the end of the turn: writeAdapter() on every field in a row mixes up neighbors (a preset changes four at once)
        onAdapterUpdated: Qt.callLater(file.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) this.writeAdapter(); } // first run: file with defaults

        // defaults -- as in the hypr config now, so the first run does not shift anything
        JsonAdapter {
            id: adapter
            // Display
            property real monScale: 0      // 0 -- auto, hypr decides
            property int refresh: 0        // 0 -- the screen's highest rate, like mode = "highres" in hyprland.lua
            property string main: ""       // whose monScale and refresh are (Rules.mon); empty -- the first monitor read decides
            // the other screens, if settings touched them, by Rules.key: { "TS2700-S6-1": { scale: 1, refresh: 144, pos: [-560, -1440] } };
            // pos is relative to the main screen, which then sits at 0x0
            property var outs: ({})
            property int brightness: 62
            property bool night: false
            property int warmth: 4300
            property int gapsIn: 6
            property int gapsOut: 14
            property int border: 2
            property bool resizeBorders: true // resize_on_border: grab a window's border or corner and drag (windows())
            property int rounding: 0
            property bool blur: true
            property bool shadow: true
            property bool motion: true
            property bool ultra: false   // battery saver mode (setMode 0; the key keeps its old name): 60 Hz and no decorations on top of the settings
            property bool game: false    // game mode, like caelestia: no animations, blur, shadows, gaps or rounding, tearing (Theme.apply)
            // what game mode keeps (settings -> windows -> in a game); tearing is always on in it (Isaqdn03's choices)
            property bool gameGaps: false   // gaps, border and rounding as set
            property bool gameMotion: false // animations
            property bool gameBlur: false
            property bool gameShadow: false
            property bool gameDnd: true     // auto game mode (services/Game) turns on do not disturb
            property bool powerAuto: false  // battery saver on battery, by itself (services/PowerAuto): unplug -- saver; plug in -- the mode you had comes back
            // Colors
            property int palette: 0
            property bool paintHypr: true
            property bool paintKitty: true
            // hands off (SenulMapa's guards, as settings): off -- the shell never writes that part of
            // the hypr config; for a rotated screen or a hand-built input setup it would fight you
            property bool manageMonitor: true
            property bool manageInput: true
            // Input -- as in hyprland/input.lua
            property int kbSwitch: 0      // index in switches
            property int repeatDelay: 250
            property int repeatRate: 35
            property bool natural: true
            property bool tap: true
            property bool typingOff: false
            property int scroll: 30       // % — scroll_factor 0.3
            property int sens: 0          // -100…100 → sensitivity -1…1
            property bool flat: false
            // the mouse's own pair (the ones above under touchpad are the pad's):
            // top-level input keywords, so the wheel inverts/speeds without touching the pad
            property bool mouseNatural: false
            property int mouseScroll: 100 // % — the mouse's scroll_factor 1.0
            // Idle: minutes, 0 -- never
            property int lockAfter: 3
            property int dpmsAfter: 5
            property int sleepAfter: 10
            property bool hibernate: true // suspend-then-hibernate
            // System
            property bool roman: true
            // Notices. Do not disturb (also set by charms): regular notifications are not shown, critical ones -- always
            property bool dnd: false
            property int noteTime: 6      // s, if the app did not set its own; 0 -- wait until dismissed
            property int noteDeck: 5      // how many are visible in the deck
        }
    }

    // kitty: include file with palette colors (kitty.conf includes it), SIGUSR1 -- reload the config
    FileView { id: kitty; path: root.dir + "/kitty.conf"; printErrors: false }

    function hypr(lua) { Quickshell.execDetached(["hyprctl", "eval", lua]); }

    // monitors from hyprctl monitors all -- enabled and not mirrors: w x h and rates are the current mode and its rates,
    // x, y, lw x lh -- where it is and how many logical px it spans (rotated -- swapped)
    property var mons: []
    // the main one -- the one monScale and refresh apply to (demonshot reads them too): the built-in, even disabled
    // (lid shut in a dock), else the first. Remembered in store.main by MODEL (no model -- by port): on a desktop the
    // screen order changes as things plug in, and a cable moves to another port or a dock -- the scale must not land
    // on another screen. An old store.main holding a port name is still found
    property string first: ""
    readonly property var mon: mons.find(m => m.name === (store.main || first)) ?? mons.find(m => m.model && m.model === (store.main || first))
        ?? { name: "", w: 0, h: 0, x: 0, y: 0, lw: 0, lh: 0, transform: 0, scale: 1, hz: 0, rates: [] }
    property bool monWanted: false // monitor() was called before the hyprctl reply arrived
    property bool driving: false   // this process drives the monitors (monitor() called by shell.qml); the lock only reads
    Process {
        id: monProc
        running: true
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const all = JSON.parse(text);
                const f = all.find(m => /^(eDP|LVDS|DSI)/.test(m.name)) ?? all.find(m => !m.disabled);
                root.first = f ? f.model.trim() || f.name : "";
                root.mons = all.filter(m => !m.disabled && m.mirrorOf === "none").map(m => {
                    const rates = [...new Set(m.availableModes.map(s => /(\d+)x(\d+)@([\d.]+)/.exec(s))
                        .filter(r => r && +r[1] === m.width && +r[2] === m.height).map(r => Math.round(+r[3])))].sort((a, b) => a - b);
                    const t = m.transform % 2, lw = Math.round(m.width / m.scale), lh = Math.round(m.height / m.scale);
                    return { name: m.name, model: m.model.trim(), desc: m.description, w: m.width, h: m.height, x: m.x, y: m.y, lw: t ? lh : lw, lh: t ? lw : lh,
                             transform: m.transform, scale: m.scale, hz: Math.round(m.refreshRate), rates: rates.length ? rates : [Math.round(m.refreshRate)] };
                });
                if (root.monWanted) root.monitor();
                else root.settle();
            }
        }
    }
    // auto -- hypr chooses the scale; which one it got, we learn by re-reading the monitors
    Timer { id: monReread; interval: 500; onTriggered: monProc.running = true }
    // what a screen is recorded under in outs: its model -- it is the monitor, not the port (a projector in the same HDMI
    // does not take the home monitor's place and rates; the home one through another port keeps its own); two identical
    // monitors, or one without a model -- the port name. Like Theme.sid
    function key(m) { return m.model && mons.filter(x => x.model === m.model).length === 1 ? m.model : m.name; }
    // a screen's own entry; by name -- the entry of a twin currently alone (its key became the model)
    function out(m) { return store.outs[key(m)] ?? store.outs[m.name]; }
    // what is chosen for a screen: scale (0 -- auto) and refresh
    function want(m) {
        if (m.name === mon.name) return { scale: store.monScale, refresh: refreshHz };
        const o = out(m);
        return { scale: o?.scale ?? m.scale, refresh: o?.refresh ?? m.hz };
    }
    // the hypr rule for a screen. It replaces the config's rule entirely -- the mode (current resolution) and the
    // rotation are carried as they are. Externals sit at pos relative to the main, the main then at 0x0: on auto hypr
    // would put it right of the explicit ones. The output is key()'s: desc: of the monitor, not the port -- a shell
    // rule lives in hypr until reload, and a projector in the same port would take this monitor's place and its mode
    // ponytail: vrr, 10-bit and hdr from user.lua are dropped by a shell rule; if needed, carry them from hyprctl like transform
    function rule(m) {
        const own = m.name === mon.name, w = want(m), pos = out(m)?.pos;
        const at = own ? (mons.some(x => x.name !== m.name && out(x)?.pos) ? "0x0" : "auto") : pos ? `${pos[0]}x${pos[1]}` : "auto";
        const output = key(m) !== m.name && m.desc ? `desc:${m.desc}` : m.name;
        return `hl.monitor({ output = ${JSON.stringify(output)}, mode = "${m.w}x${m.h}@${own ? hz : w.refresh}", position = "${at}", `
             + `scale = ${w.scale || '"auto"'}, transform = ${m.transform} })`;
    }
    // the main and the externals from outs -- in one eval, the main first: the rest stand relative to it. fresh -- re-read
    // first (a screen was plugged in): a burst of screensChanged collapses into one read 500 ms later, and the reply
    // already has the new screen. Only shell.qml calls this
    function monitor(fresh) {
        if (!store.manageMonitor) return; // settings -> displays -> arrange off: monitors are the hypr config's
        driving = true;
        if (fresh || !mons.length) {
            monWanted = true;
            if (fresh) monReread.restart();
            return;
        }
        monWanted = false;
        if (!store.main && first) store.main = first;
        const ms = mons.filter(m => m.name === mon.name || out(m)).sort((a, b) => (b.name === mon.name) - (a.name === mon.name));
        if (ms.length) hypr(ms.map(rule).join("\n"));
        monReread.restart();
    }
    // settings -> displays: scale (0 -- auto) or refresh of the screen name. The main -- monScale and refresh, an external --
    // outs (place). A scale changes the size -- settle fixes the edge to the neighbour after the re-read
    function set(name, k, v) {
        const m = mons.find(x => x.name === name);
        if (!m) return;
        if (m.name !== mon.name) return place(name, m.x, m.y, { [k]: v });
        store[k === "scale" ? "monScale" : "refresh"] = v;
        monitor();
    }
    // screen name -- at x, y (hypr logical px), extra -- its fields in outs. Every external is pinned with an explicit pos
    // relative to the main where it stands: a rule without a position would let hypr auto-place it and the neighbours shift
    function place(name, x, y, extra) {
        const b = name === mon.name ? { x, y } : mon, o = Object.assign({}, store.outs);
        for (const m of mons) {
            if (m.name === mon.name) continue;
            const p = m.name === name ? { x, y } : m;
            // an entry by port name is not deleted: if a twin returns, that screen is looked up by port again
            o[key(m)] = Object.assign({}, out(m), m.name === name ? extra : null, { pos: [p.x - b.x, p.y - b.y] });
        }
        store.outs = o;
        monitor();
    }
    // settings -> displays "forget": forget the externals' places, scales and rates -- back to the hypr config (user.lua). The
    // shell's rules live in hypr until the config is re-read -- ask for that; the rest returns via configreloaded (shell.qml)
    function forget() {
        store.outs = {};
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    function hits(a, b) { return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h; }
    // where screen r ({ x, y, w, h }, hypr logical px) lands if dropped as-is: flush against a neighbour's side, no
    // overlap, the shared edge at least a quarter of the shorter of the two; along the edge -- where it was dropped, but
    // sticking to the neighbour's edges and centre within near. Of all such places -- the nearest; none -- null
    function dock(r, others, near) {
        const stick = (v, lo, hi, to) => {
            v = Math.max(lo, Math.min(hi, v));
            return to.find(t => Math.abs(t - v) < near) ?? v;
        };
        let best = null, bd = Infinity;
        for (const o of others) {
            const kx = Math.min(r.w, o.w) / 4, ky = Math.min(r.h, o.h) / 4;
            const x = stick(r.x, o.x - r.w + kx, o.x + o.w - kx, [o.x, o.x + o.w - r.w, o.x + (o.w - r.w) / 2]);
            const y = stick(r.y, o.y - r.h + ky, o.y + o.h - ky, [o.y, o.y + o.h - r.h, o.y + (o.h - r.h) / 2]);
            for (const c of [{ x: o.x - r.w, y }, { x: o.x + o.w, y }, { x, y: o.y - r.h }, { x, y: o.y + o.h }]) {
                const p = { x: Math.round(c.x), y: Math.round(c.y), w: r.w, h: r.h }, d = Math.hypot(p.x - r.x, p.y - r.y);
                if (d < bd && !others.some(q => hits(p, q))) {
                    best = p;
                    bd = d;
                }
            }
        }
        return best;
    }
    // an external with an explicit pos overlapped a neighbour or floats in the air (scale changed, a screen returned, a
    // neighbour was dragged) -- to the nearest free edge, one per read. If we already asked for exactly there and hypr
    // did not put it -- do not insist, or it loops every half second. Tolerance 2 px -- logical-size rounding
    function settle() {
        if (!driving || mons.length < 2) return;
        const box = m => ({ x: m.x, y: m.y, w: m.lw, h: m.lh }), near = (a, b) => Math.abs(a - b) <= 2;
        const touch = (a, b) => (near(a.x + a.w, b.x) || near(b.x + b.w, a.x)) && a.y < b.y + b.h && b.y < a.y + a.h
                             || (near(a.y + a.h, b.y) || near(b.y + b.h, a.y)) && a.x < b.x + b.w && b.x < a.x + a.w;
        for (const m of mons) {
            const pos = out(m)?.pos;
            if (m.name === mon.name || !pos) continue;
            const r = box(m), rest = mons.filter(x => x !== m).map(box);
            if (!rest.some(o => hits({ x: r.x + 2, y: r.y + 2, w: r.w - 4, h: r.h - 4 }, o)) && rest.some(o => touch(r, o))) continue;
            const d = dock(r, rest, 0);
            if (d && (d.x - mon.x !== pos[0] || d.y - mon.y !== pos[1])) return place(m.name, d.x, d.y);
        }
    }
    readonly property var rates: mon.rates.length ? mon.rates : [60, 120]
    readonly property int refreshHz: store.refresh ? rates.reduce((a, b) => Math.abs(b - store.refresh) < Math.abs(a - store.refresh) ? b : a) : rates[rates.length - 1]
    readonly property real scale: store.monScale || mon.scale || 1 // what is actually set, including with auto
    readonly property var scales: ["auto", "1", "1.25", "1.5", "2"]
    function windows() {
        const s = store;
        hypr(`hl.config({ general = { gaps_in = ${s.gapsIn}, gaps_out = ${s.gapsOut}, border_size = ${s.border}, resize_on_border = ${s.resizeBorders}, extend_border_grab_area = 12 }, `
           + `decoration = { rounding = ${s.rounding}, blur = { enabled = ${blurOn} }, shadow = { enabled = ${shadowOn} } } })`);
    }
    // ponytail: on/off only; slam/snap -- override the curves from animations.lua
    function motion() { hypr(`hl.config({ animations = { enabled = ${moving} } })`); }
    readonly property var switches: [["alt+shift", "grp:alt_shift_toggle"], ["caps", "grp:caps_toggle"], ["ctrl+shift", "grp:ctrl_shift_toggle"]]
    function input() {
        if (!store.manageInput) return; // settings -> keyboard -> shell sets input off: keyboard/mouse are the hypr config's
        const s = store;
        hypr(`hl.config({ input = { kb_options = "${switches[s.kbSwitch]?.[1] ?? switches[0][1]}", repeat_delay = ${s.repeatDelay}, repeat_rate = ${s.repeatRate}, `
           + `sensitivity = ${s.sens / 100}, accel_profile = "${s.flat ? "flat" : "adaptive"}", natural_scroll = ${s.mouseNatural}, scroll_factor = ${s.mouseScroll / 100}, `
           + `touchpad = { natural_scroll = ${s.natural}, tap_to_click = ${s.tap}, disable_while_typing = ${s.typingOff}, scroll_factor = ${s.scroll / 100} } } })`);
    }
    // hibernation is not available everywhere (needs swap for resume, zram does not count) -- we ask logind. No -- regular sleep, the items
    // of hibernation are hidden. The reply arrived after idle() -- rewrite the config (the lock does not call idle(), so it is unaffected)
    property bool canHibernate: false
    property bool idleDone: false
    readonly property bool hibernateOn: store.hibernate && canHibernate
    onCanHibernateChanged: if (idleDone) idle()
    Process {
        running: true
        command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanSuspendThenHibernate"]
        stdout: StdioCollector { onStreamFinished: root.canHibernate = text.includes('"yes"') }
    }
    // hypridle does not re-read the config on the fly: we write our own and restart it. Same text and hypridle alive -- leave it,
    // so a shell restart does not reset the idle counter. inhibit_sleep = 3 -- sleep waits until the lock is up (hypridle itself
    // only waits like that for hyprlock): otherwise the machine slept with qs half-started, and on wake the monitors blink --
    // one dropping in the first ~0.5 s of the lock's life kills qs
    function idle() {
        idleDone = true;
        const s = store, dpms = a => `hyprctl eval 'hl.dispatch(hl.dsp.dpms({action = "${a}"}))'`;
        const at = (min, on, back) => min ? `\nlistener {\n    timeout = ${min * 60}\n    on-timeout = ${on}${back ? `\n    on-resume = ${back}` : ""}\n}\n` : "";
        const conf = "# demonshot: written by Rules.idle() from rules.json, do not edit by hand\n"
            + "general {\n    lock_cmd = ~/.config/quickshell/rice/rice lock\n    inhibit_sleep = 3\n"
            + `    before_sleep_cmd = loginctl lock-session\n    after_sleep_cmd = ${dpms("on")}\n}\n`
            + at(s.lockAfter, "loginctl lock-session") + at(s.dpmsAfter, dpms("off"), dpms("on"))
            + at(s.sleepAfter, hibernateOn ? "systemctl suspend-then-hibernate" : "systemctl suspend");
        Quickshell.execDetached(["sh", "-c", 'f="$1/hypridle.conf"; printf %s "$2" | cmp -s - "$f" && pgrep -x hypridle >/dev/null && exit; '
                                       + 'printf %s "$2" > "$f"; pkill -x hypridle; exec hypridle -c "$f"', "sh", dir, conf]);
    }
    function brightness() { Quickshell.execDetached(["brightnessctl", "-q", "set", store.brightness + "%"]); }
    function night() {
        Quickshell.execDetached(["sh", "-c", store.night ? `pkill -x hyprsunset; exec hyprsunset -t ${store.warmth}` : "pkill -x hyprsunset"]);
    }

    // palette: Theme repaints itself (bindings on pal), here -- what lives outside the shell
    function paint() {
        const c = pal.c;
        if (store.paintHypr) {
            const h = c.map(x => x.slice(1));
            hypr(`hl.config({ general = { col = { active_border = { colors = { "rgb(${h[5]})", "rgb(${h[4]})", "rgb(${h[5]})" }, angle = 135 }, `
               + `inactive_border = "rgb(${h[2]})" } }, decoration = { shadow = { color = "rgba(${h[5]}20)" } } })`);
        }
        if (store.paintKitty) {
            kitty.setText([
                ["foreground", c[7]], ["background", c[1]], ["cursor", c[7]], ["cursor_text_color", c[1]],
                ["selection_foreground", c[7]], ["selection_background", c[3]], ["url_color", c[4]],
                ["active_border_color", c[5]], ["inactive_border_color", c[2]],
                ["active_tab_foreground", c[7]], ["active_tab_background", c[5]],
                ["inactive_tab_foreground", c[6]], ["inactive_tab_background", c[1]], ["tab_bar_background", c[0]]
            ].map(([k, v]) => `${k} ${v}`).join("\n") + "\n");
            Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"]);
        }
    }

    // is anything serving the profiles? PowerProfiles (Quickshell.Services.UPower) is only a proxy:
    // with no daemon behind it the profile reads a stale default and setting it goes nowhere, silently.
    // powerprofilesctl is the daemon's own tool and answers only when a daemon does (power-profiles-daemon
    // itself, or tuned's ppd emulation) -- sh -c so a missing tool is a plain nonzero exit, not a spawn
    // failure. Probed at startup and whenever settings -> battery opens (checkPower); the page says when it's out
    property bool powerOk: true
    Process {
        id: powerProbe
        running: true
        command: ["sh", "-c", "powerprofilesctl get 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: if (/power-saver|balanced|performance/.test(text)) root.powerOk = true; }
        onExited: code => { if (code !== 0) root.powerOk = false; }
    }
    function checkPower() { powerProbe.running = true; }

    // power modes, like caelestia: power-profiles-daemon profile. battery saver on top -- 60 Hz, no animations, blur or shadows,
    // on top of your settings without touching them: exit -- they return. 0 battery saver . 1 saver . 2 balanced . 3 performance.
    // Windows (blur, shadows) are applied by the caller: demonshot -- windows(), galaga -- Theme.apply() (windows() would remove its rounding)
    readonly property var modes: [
        { name: "battery saver", short: "BAT", what: `power saver · ${rates[0]} hz · still` },
        { name: "saver", short: "ECO", what: "power saver" },
        { name: "balanced", short: "BAL", what: "balanced" },
        { name: "performance", short: "MAX", what: "performance" }
    ]
    readonly property int mode: store.ultra ? 0 : PowerProfiles.profile + 1
    readonly property int modeCount: PowerProfiles.hasPerformanceProfile ? 4 : 3
    function setMode(i) {
        i = Math.max(0, Math.min(modeCount - 1, i));
        const hz0 = hz, moving0 = moving;
        store.ultra = i === 0;
        PowerProfiles.profile = i === 0 ? PowerProfile.PowerSaver : i - 1;
        // monitor -- only the main one and only if the refresh rate is really different: reconfiguring the output
        // blinks the screen and resets hover (panels go dark)
        if (hz !== hz0 && mon.name) {
            hypr(rule(mon));
            monReread.restart();
        }
        if (moving !== moving0) motion();
    }
    // what is actually set: battery saver overrides the settings -- the lowest screen refresh rate, otherwise the closest to the selected
    readonly property int hz: store.ultra ? rates[0] : refreshHz
    readonly property bool moving: store.motion && !store.ultra && (!store.game || store.gameMotion)
    readonly property bool blurOn: store.blur && !store.ultra && (!store.game || store.gameBlur)
    readonly property bool shadowOn: store.shadow && !store.ultra && (!store.game || store.gameShadow)

    // shell startup: everything except brightness (it is changed by the keys and OSD, we must not overwrite it on every launch)
    function applyAll() {
        monitor(); windows(); motion(); night(); paint(); input(); idle();
    }
}
