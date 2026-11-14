pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs
import qs.settings

// windows-style snapping (settings -> windows -> snapping). Super+arrows snap the
// focused window into halves, corners and the full work area; Super+Z opens the
// layouts popup (snap/SnapPop.qml), which fills a layout's spaces one pick at a
// time (snap assist). The layout engine is dwindle, so a snapped window FLOATS at
// an exact size; unsnapping gives back whatever it was before the first snap --
// tiled, or floating at its old geometry, kept per window in recs.
//
// Groups: windows placed by one action (an arrow snap plus its assist picks, a
// layout plus its picks) share a group -- and so does any set of records whose
// placed rects share a full edge. regroup() rebuilds the groups per workspace
// from the stored rects after every placement, so the rule is one and the same
// however the windows got there. A group never spans workspaces, and holds at
// most four windows (the grid is the largest layout).
//
// Geometry has no hyprland event and a toplevel's lastIpcObject is a snapshot
// from the last full fetch, so actions and the group watcher both read fresh
// `hyprctl clients -j` / `monitors -j` (the Game service's Process shape). The
// watcher polls every 200 ms, only while a group exists. Our own dispatch
// batches are fenced by a 150 ms guard so the poll never mistakes one of our
// placements for the user dragging a window away.
Singleton {
    id: root

    // addr (hyprctl form, with 0x) -> { zone, rect, lastZone, pre { floating, x, y, w, h }, ws }
    property var recs: ({})
    // group id -> [addr]
    property var groups: ({})
    property int gidSeq: 0
    property double guardUntil: 0

    // the layouts popup's state -- snap/SnapPop.qml only renders this
    property bool popOpen: false
    property string popMode: ""    // "layouts" | "assist"
    property var assistZones: []   // [{ zone, frac, rect, label }] still to fill, in order
    property var assistCands: []   // [{ addr, title, cls }] the other windows on assistWs
    property int assistWs: -1

    // canonical zones as fractions of the gap-inset work area
    readonly property var zf: ({
        L: [0, 0, 0.5, 1], R: [0.5, 0, 0.5, 1], T: [0, 0, 1, 0.5], B: [0, 0.5, 1, 0.5],
        TL: [0, 0, 0.5, 0.5], TR: [0.5, 0, 0.5, 0.5], BL: [0, 0.5, 0.5, 0.5], BR: [0.5, 0.5, 0.5, 0.5],
        MAX: [0, 0, 1, 1]
    })
    readonly property var zlabel: ({ L: "left half", R: "right half", T: "top half", B: "bottom half",
        TL: "top left", TR: "top right", BL: "bottom left", BR: "bottom right", MAX: "the whole screen" })
    // the popup's six layouts: zone 1 takes the focused window, the rest are assist picks
    readonly property var layouts: [
        { name: "side by side", zones: [
            { f: [0, 0, 0.5, 1], zone: "L", label: "left half" },
            { f: [0.5, 0, 0.5, 1], zone: "R", label: "right half" }] },
        { name: "stacked", zones: [
            { f: [0, 0, 1, 0.5], zone: "T", label: "top half" },
            { f: [0, 0.5, 1, 0.5], zone: "B", label: "bottom half" }] },
        { name: "three columns", zones: [
            { f: [0, 0, 1 / 3, 1], zone: "lay", label: "left column" },
            { f: [1 / 3, 0, 1 / 3, 1], zone: "lay", label: "middle column" },
            { f: [2 / 3, 0, 1 / 3, 1], zone: "lay", label: "right column" }] },
        { name: "grid", zones: [
            { f: [0, 0, 0.5, 0.5], zone: "TL", label: "top left" },
            { f: [0.5, 0, 0.5, 0.5], zone: "TR", label: "top right" },
            { f: [0, 0.5, 0.5, 0.5], zone: "BL", label: "bottom left" },
            { f: [0.5, 0.5, 0.5, 0.5], zone: "BR", label: "bottom right" }] },
        { name: "main + side", zones: [
            { f: [0, 0, 0.6, 1], zone: "lay", label: "main" },
            { f: [0.6, 0, 0.4, 1], zone: "lay", label: "side" }] },
        { name: "side + main", zones: [
            { f: [0, 0, 0.4, 1], zone: "lay", label: "side" },
            { f: [0.4, 0, 0.6, 1], zone: "lay", label: "main" }] }
    ]

    // ---- fresh state: one fetch feeds one action, or one watcher tick ----

    property var snapC: null // last clients list
    property var snapM: null // last monitors list
    property var snapA: null // last activewindow object ({} when nothing is focused)
    property bool fetching: false
    property bool haveC: false
    property bool haveM: false
    property bool haveA: false
    property var pendingAct: null

    Process {
        id: pc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.snapC = JSON.parse(text); } catch (e) { root.snapC = null; }
                root.haveC = true;
                root.fetched();
            }
        }
    }
    Process {
        id: pm
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.snapM = JSON.parse(text); } catch (e) { root.snapM = null; }
                root.haveM = true;
                root.fetched();
            }
        }
    }
    Process {
        id: pa
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.snapA = JSON.parse(text); } catch (e) { root.snapA = null; }
                root.haveA = true;
                root.fetched();
            }
        }
    }
    // act runs once all three are in; with no act the fetch feeds the watcher
    function fetch(act) {
        if (act) pendingAct = act;
        if (fetching) return;
        fetching = true;
        haveC = false;
        haveM = false;
        haveA = false;
        pc.running = true;
        pm.running = true;
        pa.running = true;
    }
    function fetched() {
        if (!haveC || !haveM || !haveA) return;
        fetching = false;
        const act = pendingAct;
        pendingAct = null;
        if (act) act();
        else observe();
    }
    Timer {
        interval: 200
        repeat: true
        running: Object.keys(root.groups).length > 0
        onTriggered: if (!root.fetching && !root.pendingAct) root.fetch(null)
    }

    // ---- snapshot helpers ----

    function client(addr) {
        return (snapC ?? []).find(c => c.address === addr) ?? null;
    }
    function focusedAddr() {
        // the focused window comes from the same hyprctl fetch as everything
        // else, so its address is already in the client list's 0x form and
        // client() finds it. (The toplevel manager's address never matched
        // the list, and every entry point silently found no window at all.)
        return snapA?.address ?? "";
    }
    function monOf(c) {
        return (snapM ?? []).find(m => m.id === c.monitor) ?? (snapM ?? []).find(m => m.focused) ?? null;
    }
    // the work area in logical px: the monitor's rect minus what the layers reserve
    function workarea(m) {
        const w = Math.round(m.width / m.scale), h = Math.round(m.height / m.scale);
        const r = m.reserved ?? [0, 0, 0, 0];
        return { x: m.x + r[0], y: m.y + r[1], w: w - r[0] - r[2], h: h - r[1] - r[3] };
    }
    // a zone rect: the fraction of the work area, inset by gaps out at the edges
    // and by half of gaps in on every shared edge -- two snapped halves sit
    // exactly gaps-in apart, like the tiler's own windows
    function zoneRect(f, wa) {
        const go = Rules.store.gapsOut, gi = Rules.store.gapsIn;
        const x0 = wa.x + go, y0 = wa.y + go, w = wa.w - 2 * go, h = wa.h - 2 * go;
        let x = x0 + f[0] * w, y = y0 + f[1] * h, zw = f[2] * w, zh = f[3] * h;
        if (f[0] > 0) { x += gi / 2; zw -= gi / 2; }
        if (f[1] > 0) { y += gi / 2; zh -= gi / 2; }
        if (f[0] + f[2] < 1) zw -= gi / 2;
        if (f[1] + f[3] < 1) zh -= gi / 2;
        return { x: Math.round(x), y: Math.round(y), w: Math.round(zw), h: Math.round(zh) };
    }
    function rectOf(c) {
        return { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] };
    }
    function rectEq(a, b, tol) {
        return a && b && Math.abs(a.x - b.x) <= tol && Math.abs(a.y - b.y) <= tol
            && Math.abs(a.w - b.w) <= tol && Math.abs(a.h - b.h) <= tol;
    }

    // ---- dispatchers (hyprland's lua api, addressed like the deck addresses windows) ----

    function dsp(s) { Hyprland.dispatch(s); }
    function moveStr(a, r) { return `hl.dsp.window.move({ x = ${r.x}, y = ${r.y}, relative = false, window = "address:${a}" })`; }
    function resizeStr(a, r) { return `hl.dsp.window.resize({ x = ${r.w}, y = ${r.h}, window = "address:${a}" })`; }
    function floatStr(a, on) { return `hl.dsp.window.float({ action = "${on ? "on" : "off"}", window = "address:${a}" })`; }
    function guard() { guardUntil = Date.now() + 150; }

    // ---- records ----

    function saveRec(addr, rec) {
        const n = Object.assign({}, recs);
        n[addr] = rec;
        recs = n;
    }
    function dropRec(addr) {
        if (!(addr in recs)) return;
        const n = Object.assign({}, recs);
        delete n[addr];
        recs = n;
    }
    function groupOf(addr) {
        for (const g in groups) if (groups[g].includes(addr)) return g;
        return "";
    }
    // full-edge sharing between two placed rects: the edge coincides and both
    // windows run its whole length
    function shareV(a, b) { return Math.abs(a.x + a.w - b.x) <= 2 && Math.abs(a.y - b.y) <= 2 && Math.abs(a.h - b.h) <= 2; }
    function shareH(a, b) { return Math.abs(a.y + a.h - b.y) <= 2 && Math.abs(a.x - b.x) <= 2 && Math.abs(a.w - b.w) <= 2; }
    function linked(a, b) { return shareV(a, b) || shareV(b, a) || shareH(a, b) || shareH(b, a); }
    function regroupWs(ws) {
        const mine = Object.keys(recs).filter(a => recs[a].ws === ws);
        const old = groups, ng = {};
        for (const g in old)
            if (!old[g].some(a => recs[a] && recs[a].ws === ws)) ng[g] = old[g];
        const seen = {};
        for (const a of mine) {
            if (seen[a]) continue;
            const comp = [], stack = [a];
            seen[a] = true;
            while (stack.length) {
                const x = stack.pop();
                comp.push(x);
                for (const b of mine)
                    if (!seen[b] && linked(recs[x].rect, recs[b].rect)) { seen[b] = true; stack.push(b); }
            }
            if (comp.length < 2) continue;
            const key = comp.slice().sort().join(",");
            const keep = Object.keys(old).find(g => old[g].slice().sort().join(",") === key);
            ng[keep ?? ("g" + (++gidSeq))] = comp;
        }
        groups = ng;
    }

    // ---- placing and restoring ----

    // snap one window into a rect. The first snap of a window captures what it
    // was (tiled, or floating where) -- that is what restore gives back.
    function place(addr, rect, zone) {
        const c = client(addr);
        if (!c) return;
        let rec = recs[addr];
        if (!rec) {
            rec = { zone: "", rect: null, lastZone: "", ws: c.workspace.id,
                    pre: { floating: !!c.floating, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] } };
        }
        if (rec.zone && rec.zone !== zone) rec.lastZone = rec.zone;
        if ((c.fullscreen ?? 0) > 0)
            dsp(`hl.dsp.window.fullscreen({ mode = "fullscreen", action = "off", window = "address:${addr}" })`);
        if (!c.floating) dsp(floatStr(addr, true));
        dsp(resizeStr(addr, rect));
        dsp(moveStr(addr, rect));
        rec.zone = zone;
        rec.rect = rect;
        rec.ws = c.workspace.id;
        saveRec(addr, rec);
        guard();
        Sounds.play("tick");
    }
    function restore(addr) {
        const rec = recs[addr];
        if (!rec) return;
        const ws = rec.ws, pre = rec.pre;
        dropRec(addr);
        if (pre.floating) {
            dsp(resizeStr(addr, pre));
            dsp(moveStr(addr, pre));
        } else {
            dsp(floatStr(addr, false)); // the tiler takes it back
        }
        guard();
        Sounds.play("tick");
        regroupWs(ws);
    }
    function minimise(addr) {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/minimise.sh", addr]);
    }

    // ---- super+arrows ----

    function snapDir(dir) {
        if (!Theme.state.snap) { // off: the arrows are focus keys again, as they were
            Hyprland.dispatch(`hl.dsp.focus({ direction = "${dir}" })`);
            return;
        }
        fetch(() => snapDirNow(dir));
    }
    function snapDirNow(dir) {
        const addr = focusedAddr();
        if (!addr) return;
        const c = client(addr);
        if (!c || c.workspace.id < 0) return; // parked or nowhere: nothing to snap
        const mon = monOf(c);
        if (!mon) return;
        const wa = workarea(mon), rec = recs[addr], zone = rec?.zone ?? "";
        let target = "", frac = null;
        if (dir === "left") {
            if (zone === "L") return;
            target = "L"; frac = zf.L;
        } else if (dir === "right") {
            if (zone === "R") return;
            target = "R"; frac = zf.R;
        } else if (dir === "up") {
            if (zone === "MAX") return;
            if (zone === "L") { target = "TL"; frac = zf.TL; }
            else if (zone === "R") { target = "TR"; frac = zf.TR; }
            else if (zone === "BL") { target = "L"; frac = zf.L; }
            else if (zone === "BR") { target = "R"; frac = zf.R; }
            else if (zone === "B") {
                const left = c.at[0] + c.size[0] / 2 < wa.x + wa.w / 2;
                target = left ? "BL" : "BR"; frac = left ? zf.BL : zf.BR;
            } else { target = "MAX"; frac = zf.MAX; } // free, T, TL, TR, a layout space
        } else { // down
            if (!rec) { minimise(addr); return; }
            if (zone === "TL" || zone === "BL") { target = "L"; frac = zf.L; }
            else if (zone === "TR" || zone === "BR") { target = "R"; frac = zf.R; }
            else if (zone === "MAX" && rec.lastZone && zf[rec.lastZone]) { target = rec.lastZone; frac = zf[rec.lastZone]; }
            else { restore(addr); return; } // a half, a layout space, or MAX with nowhere to go back to
        }
        place(addr, zoneRect(frac, wa), target);
        regroupWs(c.workspace.id);
        maybeAssist(addr, target, wa, c.workspace.id);
    }

    // ---- snap assist ----

    function complements(zone) {
        return ({ L: ["R"], R: ["L"], T: ["B"], B: ["T"],
                  TL: ["TR", "BL", "BR"], TR: ["TL", "BR", "BL"],
                  BL: ["TL", "BR", "TR"], BR: ["TR", "BL", "TL"] })[zone] ?? [];
    }
    function candidates(ws, exclude) {
        return (snapC ?? [])
            .filter(c => c.workspace.id === ws && c.address !== exclude)
            .map(c => ({ addr: c.address, title: c.title || c.class || "", cls: c.class ?? "" }));
    }
    // after an arrow snap: if the rest of the shape is empty and there is
    // anything to fill it with, the popup offers those windows one at a time
    function maybeAssist(addr, zone, wa, ws) {
        if (!Theme.state.snapAssist) return;
        const comp = complements(zone);
        if (!comp.length) return;
        const empty = comp
            .map(z => ({ zone: z, frac: zf[z], rect: zoneRect(zf[z], wa), label: zlabel[z] }))
            .filter(z => !Object.keys(recs).some(a => recs[a].ws === ws && rectEq(recs[a].rect, z.rect, 6))
                      && !(snapC ?? []).some(c => c.address !== addr && c.workspace.id === ws && rectEq(rectOf(c), z.rect, 6)));
        if (!empty.length) return;
        const cands = candidates(ws, addr);
        if (!cands.length) return;
        assistZones = empty;
        assistWs = ws;
        assistCands = cands;
        popMode = "assist";
        popOpen = true;
    }
    function chooseAssist(addr) {
        if (popMode !== "assist" || !assistZones.length) return;
        const z = assistZones[0];
        fetch(() => {
            const c = client(addr);
            if (!c) { popCancel(); return; }
            const mon = monOf(c);
            if (!mon) { popCancel(); return; }
            place(addr, zoneRect(z.frac, workarea(mon)), z.zone);
            regroupWs(assistWs);
            assistZones = assistZones.slice(1);
            assistCands = candidates(assistWs, "");
            if (!assistZones.length || !assistCands.length) popClose();
        });
    }

    // ---- the layouts popup (super+z) ----

    function toggleLayouts() {
        if (popOpen) { popCancel(); return; }
        if (!Theme.state.snap) return;
        popMode = "layouts";
        popOpen = true;
        Sounds.play("pop");
    }
    function chooseLayout(i) {
        const lay = layouts[i];
        if (!lay || popMode !== "layouts") return;
        fetch(() => {
            const addr = focusedAddr(), c = addr ? client(addr) : null;
            if (!c || c.workspace.id < 0) { popCancel(); return; }
            const mon = monOf(c);
            if (!mon) { popCancel(); return; }
            const wa = workarea(mon), z0 = lay.zones[0];
            place(addr, zoneRect(z0.f, wa), z0.zone);
            regroupWs(c.workspace.id);
            const rest = lay.zones.slice(1).map(z => ({ zone: z.zone, frac: z.f, rect: zoneRect(z.f, wa), label: z.label }));
            const cands = candidates(c.workspace.id, addr);
            if (Theme.state.snapAssist && rest.length && cands.length) {
                assistZones = rest;
                assistWs = c.workspace.id;
                assistCands = cands;
                popMode = "assist"; // the popup stays up and turns into the picker
            } else popClose();
        });
    }
    // a whole layout at once: windows[k] takes zones[k], no picking
    function applyLayout(i, addrs) {
        const lay = layouts[i];
        if (!lay) return;
        fetch(() => {
            const first = addrs.length ? client(addrs[0]) : null;
            if (!first) return;
            const mon = monOf(first);
            if (!mon) return;
            const wa = workarea(mon);
            addrs.slice(0, lay.zones.length).forEach((a, k) => place(a, zoneRect(lay.zones[k].f, wa), lay.zones[k].zone));
            regroupWs(first.workspace.id);
        });
    }
    function popClose() {
        popOpen = false;
        popMode = "";
        assistZones = [];
        assistCands = [];
    }
    function popCancel() { popClose(); } // esc / super+z again: placed windows keep their group

    // ---- the watcher: membership and geometry, while any group exists ----

    function observe() {
        if (!snapC) return;
        const touched = {};
        for (const addr of Object.keys(recs)) {
            const rec = recs[addr], c = client(addr);
            // closed, moved to another desktop, fullscreen, or back in the
            // tiler's hands: the record is done, the window is left as it is
            if (!c || c.workspace.id !== rec.ws || (c.fullscreen ?? 0) > 0 || !c.floating) {
                touched[rec.ws] = true;
                dropRec(addr);
                continue;
            }
            const cur = rectOf(c);
            if (rectEq(cur, rec.rect, 0)) continue;
            if (Date.now() < guardUntil) { // our own placement landing: just learn it
                rec.rect = cur;
                saveRec(addr, rec);
                continue;
            }
            // the user took it: dragged away, or resized out of its space.
            // Either way it is a free window again -- record cleared, left
            // floating exactly where it is.
            touched[rec.ws] = true;
            dropRec(addr);
        }
        for (const ws in touched) regroupWs(Number(ws));
    }
}
