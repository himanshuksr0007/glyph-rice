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
// most four windows (the grid is the largest layout). Grouped windows resize
// together: resize one and the watcher moves the shared boundary for its
// neighbours (linkedResize below; settings -> windows -> resize neighbours).
//
// Geometry has no hyprland event and a toplevel's lastIpcObject is a snapshot
// from the last full fetch, so actions and the group watcher both read fresh
// `hyprctl clients -j` / `monitors -j` (the Game service's Process shape). The
// watcher polls every 200 ms, only while a group exists. Our own dispatch
// batches are fenced by a 150 ms guard so the poll never mistakes one of our
// placements for the user dragging a window away.
//
// Dragging is the third way in, and the drag tracker at the bottom is its
// watcher: it samples the focused window and the cursor on its own small
// fetch. A window that moves at one size, held by one point of it, is a hand
// drag; the zone under the cursor previews (snap/SnapZone.qml), and letting
// go on an edge or a corner places the window there.
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
    // (preOver: a caller that saw the window before it moved -- the drag
    // tracker -- hands that state over; a window with a record keeps its own.)
    function place(addr, rect, zone, preOver) {
        const c = client(addr);
        if (!c) return;
        let rec = recs[addr];
        if (!rec) {
            rec = { zone: "", rect: null, lastZone: "", ws: c.workspace.id,
                    pre: preOver ?? { floating: !!c.floating, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] } };
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
            if (dragT && addr === dragT.addr) continue; // in a hand drag: its fate is decided at release
            const cur = rectOf(c);
            if (rectEq(cur, rec.rect, 0)) continue;
            if (Date.now() < guardUntil) { // our own placement landing: just learn it
                rec.rect = cur;
                saveRec(addr, rec);
                continue;
            }
            const sizeSame = cur.w === rec.rect.w && cur.h === rec.rect.h;
            if (sizeSame) {
                // dragged away whole: a free window again -- record cleared,
                // left floating exactly where it was dropped
                touched[rec.ws] = true;
                dropRec(addr);
                continue;
            }
            // resized. In a group, with linked resize on, the neighbours'
            // shared edges follow and the record learns the new rect; anywhere
            // else the window has left its space, and the record ends with it.
            const gid = groupOf(addr);
            if (Theme.state.snapLinked && gid) {
                linkedResize(addr, rec.rect, cur, gid);
                rec.rect = cur;
                saveRec(addr, rec);
            } else {
                touched[rec.ws] = true;
                dropRec(addr);
            }
        }
        for (const ws in touched) regroupWs(Number(ws));
    }

    function spansOverlap(p1, l1, p2, l2) { return p1 < p2 + l2 && p2 < p1 + l1; }
    // M was resized from oldR to newR: every group mate sharing an edge with
    // M's old rect has that boundary moved to M's new edge -- its far edge
    // stays, so it grows or shrinks into the space. In a 2x2 group a corner
    // window shares one vertical and one horizontal edge, so both mates move
    // and the cross follows. A mate that would end up under 240x160 is left.
    function linkedResize(addr, oldR, newR, gid) {
        let applied = false;
        for (const n of (groups[gid] ?? [])) {
            if (n === addr) continue;
            const nr = recs[n];
            if (!nr) continue;
            const r = nr.rect;
            let nx = r.x, ny = r.y, nw = r.w, nh = r.h, adj = false;
            if (Math.abs(oldR.x + oldR.w - r.x) <= 3 && spansOverlap(oldR.y, oldR.h, r.y, r.h)) {
                const b = newR.x + newR.w; nx = b; nw = r.x + r.w - b; adj = true;
            } else if (Math.abs(oldR.x - (r.x + r.w)) <= 3 && spansOverlap(oldR.y, oldR.h, r.y, r.h)) {
                nw = newR.x - r.x; adj = true;
            }
            if (Math.abs(oldR.y + oldR.h - r.y) <= 3 && spansOverlap(oldR.x, oldR.w, r.x, r.w)) {
                const b = newR.y + newR.h; ny = b; nh = r.y + r.h - b; adj = true;
            } else if (Math.abs(oldR.y - (r.y + r.h)) <= 3 && spansOverlap(oldR.x, oldR.w, r.x, r.w)) {
                nh = newR.y - r.y; adj = true;
            }
            if (!adj || nw < 240 || nh < 160) continue;
            const nrect = { x: nx, y: ny, w: nw, h: nh };
            dsp(resizeStr(n, nrect));
            dsp(moveStr(n, nrect));
            nr.rect = nrect;
            saveRec(n, nr);
            applied = true;
        }
        if (applied) guard();
    }

    // ---- drag snapping: drag a window to an edge or corner, let go ----

    // the drag cycle's own small fetch: clients, the active window, the
    // cursor. (The main fetch's monitors give the work areas; if they are
    // not in yet, dragTick starts that fetch and skips the tick.)
    property var dsnapC: null
    property var dsnapA: null
    property var dsnapPos: null
    property bool dFetching: false
    property bool haveDC: false
    property bool haveDA: false
    property bool haveDP: false

    Process {
        id: dc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dsnapC = JSON.parse(text); } catch (e) { root.dsnapC = null; }
                root.haveDC = true;
                root.dFetched();
            }
        }
    }
    Process {
        id: da
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dsnapA = JSON.parse(text); } catch (e) { root.dsnapA = null; }
                root.haveDA = true;
                root.dFetched();
            }
        }
    }
    Process {
        id: dpos
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                const x = parseInt(p[0]), y = parseInt(p[1]);
                root.dsnapPos = isNaN(x) || isNaN(y) ? null : { x: x, y: y };
                root.haveDP = true;
                root.dFetched();
            }
        }
    }
    function dragFetch() {
        if (dFetching) return;
        dFetching = true;
        haveDC = false;
        haveDA = false;
        haveDP = false;
        dc.running = true;
        da.running = true;
        dpos.running = true;
    }
    function dFetched() {
        if (!haveDC || !haveDA || !haveDP) return;
        dFetching = false;
        dragTick();
    }
    Timer {
        interval: 250
        repeat: true
        running: Theme.state.snap && Theme.state.snapDrag && !root.popOpen
        onTriggered: root.dragFetch()
    }

    // dragPrev: the last sample of the focused window. dragT: a drag being
    // tracked. dragZone / dragRect: the preview snap/SnapZone.qml draws.
    property var dragPrev: null // { addr, x, y, w, h, floating, cx, cy }
    property var dragT: null    // { addr, offX, offY, lastX, lastY, lastW, lastH, still, pre }
    property string dragZone: ""
    property var dragRect: null

    function dragSample(c, cur) {
        return { addr: c.address, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1],
                 floating: !!c.floating, cx: cur.x, cy: cur.y };
    }
    function dragAbort() {
        dragT = null;
        dragZone = "";
        dragRect = null;
    }
    // the zone the cursor is on: within 6 px of the work area's edges. The
    // bottom alone is not a zone -- windows maximises at the top, not there.
    function dragZoneAt(c, cur) {
        const mon = monOf(c);
        if (!mon) return null;
        const wa = workarea(mon);
        const l = cur.x <= wa.x + 6, r = cur.x >= wa.x + wa.w - 6;
        const t = cur.y <= wa.y + 6, b = cur.y >= wa.y + wa.h - 6;
        let zone = "";
        if (l && t) zone = "TL"; else if (r && t) zone = "TR";
        else if (l && b) zone = "BL"; else if (r && b) zone = "BR";
        else if (t) zone = "MAX"; else if (l) zone = "L"; else if (r) zone = "R";
        return zone ? { zone: zone, rect: zoneRect(zf[zone], wa) } : null;
    }

    function dragTick() {
        const a = dsnapA?.address ?? "", cur = dsnapPos;
        // nothing focused, no cursor, or the popup is up: no drag can be on
        if (!a || !cur || popOpen) { dragAbort(); dragPrev = null; return; }
        const c = (dsnapC ?? []).find(x => x.address === a) ?? null;
        if (!c || c.workspace.id < 0) { dragAbort(); dragPrev = null; return; } // closed, or parked away
        if (!snapM) { fetch(null); dragPrev = dragSample(c, cur); return; } // zones need the monitors first
        const r = rectOf(c);
        const offX = cur.x - r.x, offY = cur.y - r.y; // where the cursor holds the window

        if (dragT) {
            if (dragT.addr !== a) dragAbort(); // focus went elsewhere mid-drag
            else if (r.w !== dragT.lastW || r.h !== dragT.lastH
                     || Math.abs(offX - dragT.offX) > 12 || Math.abs(offY - dragT.offY) > 12) {
                dragAbort(); // resized, or moved by the keys: not a hand drag any more
            } else if (r.x !== dragT.lastX || r.y !== dragT.lastY) {
                dragT.still = 0;
                dragT.lastX = r.x;
                dragT.lastY = r.y;
                const z = dragZoneAt(c, cur);
                dragZone = z?.zone ?? "";
                dragRect = z?.rect ?? null;
                dragPrev = dragSample(c, cur);
                return;
            } else if (++dragT.still >= 2) {
                dragRelease(); // the position held for two ticks: let go
                dragPrev = null;
                return;
            } else {
                dragPrev = dragSample(c, cur);
                return;
            }
        }

        // begin: the window is floating in the fresh data, it moved since the
        // last sample at the same size, and the cursor still holds it by the
        // same point (±12 px) -- a hand drag. A grabbed tiled window is
        // floating by now (hyprland floats it as the drag starts); the
        // previous sample remembers what it was, and that state -- the
        // record's own, if it has one -- is what a restore must give back.
        const p = dragPrev;
        if (p && p.addr === a && c.floating
                && r.w === p.w && r.h === p.h && (r.x !== p.x || r.y !== p.y)
                && Math.abs(offX - (p.cx - p.x)) <= 12 && Math.abs(offY - (p.cy - p.y)) <= 12) {
            const rec = recs[a];
            dragT = { addr: a, offX: offX, offY: offY,
                      lastX: r.x, lastY: r.y, lastW: r.w, lastH: r.h, still: 0,
                      pre: rec ? rec.pre : { floating: p.floating, x: p.x, y: p.y, w: p.w, h: p.h } };
            const z = dragZoneAt(c, cur);
            dragZone = z?.zone ?? "";
            dragRect = z?.rect ?? null;
        }
        dragPrev = dragSample(c, cur);
    }

    function dragRelease() {
        const d = dragT, zone = dragZone;
        dragAbort();
        if (!d) return;
        fetch(() => dragLand(d, zone)); // land on fresh lists, so client() is true
    }
    // with a zone: place it (the tick sound is place()'s). With none: a
    // record whose window was carried somewhere else ends, and the window
    // stays a free floating window where it was dropped.
    function dragLand(d, zone) {
        const c = client(d.addr);
        if (!c || c.workspace.id < 0) return;
        if (zone) {
            const mon = monOf(c);
            if (!mon) return;
            place(d.addr, zoneRect(zf[zone], workarea(mon)), zone, d.pre);
            regroupWs(c.workspace.id);
        } else {
            const rec = recs[d.addr];
            if (rec && !rectEq(rectOf(c), rec.rect, 0)) {
                const ws = rec.ws;
                dropRec(d.addr);
                regroupWs(ws);
            }
        }
    }
}
