import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs
import "lock"

// greet -- the boot login, run by greetd (installed by ./install.sh --greeter):
//   qs -p /etc/greetd/galaga/greet.qml, under the stripped Hyprland in config/greetd/hyprland.lua.
// The face is the lock's face (lock/LockFace.qml) -- same clock, avatar, pill, dots. Only the backend
// differs: PAM (lock.qml) is swapped for Quickshell.Services.Greetd, and the name is a bubble that
// switches users. On success greetd launches the session the sddm dropdown used to offer:
// "Hyprland (uwsm-managed)", resolved below from /usr/share/wayland-sessions.
ShellRoot {
    id: shell
    // like lock.qml: no hot-reload -- a recreated window mid-auth would lose the greetd conversation
    settings.watchFiles: false

    property var users: []      // [{ name, face }] -- human users in /etc/passwd order; face may be ""
    property var sessionCmd: ["Hyprland"]

    // human users (uid 1000..59999, a real shell), each with the first readable face:
    // /var/lib/AccountsService/icons/<user>, else ~/.face. LAST is the pre-selected user:
    // our own memory of the previous login, else sddm's (it was the display manager before greetd)
    Process {
        running: true
        command: ["sh", "-c",
            "last=\"\"\n" +
            "for f in \"${XDG_STATE_HOME:-$HOME/.local/state}/galaga-greeter/last-user\" /var/lib/sddm/state.conf; do\n" +
            "  [ -r \"$f\" ] || continue\n" +
            "  case \"$f\" in\n" +
            "    *sddm/state.conf) last=$(sed -n 's/^User=//p' \"$f\" | tail -n 1) ;;\n" +
            "    *) last=$(head -n 1 \"$f\" | tr -d ' \\t\\r') ;;\n" +
            "  esac\n" +
            "  [ -n \"$last\" ] && break\n" +
            "done\n" +
            "printf 'LAST\\t%s\\n' \"$last\"\n" +
            "getent passwd | while IFS=: read -r name _pw uid _gid _gecos home sh; do\n" +
            "  [ \"$uid\" -ge 1000 ] 2>/dev/null || continue\n" +
            "  [ \"$uid\" -lt 60000 ] || continue\n" +
            "  case \"$sh\" in */nologin|*/false|\"\") continue ;; esac\n" +
            "  face=\"\"\n" +
            "  for c in \"/etc/greetd/faces/$name\" \"/var/lib/AccountsService/icons/$name\" \"$home/.face\"; do\n" +
            "    if [ -r \"$c\" ]; then face=\"$c\"; break; fi\n" +
            "  done\n" +
            "  printf 'USER\\t%s\\t%s\\n' \"$name\" \"$face\"\n" +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                let last = "";
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "LAST") last = p[1] || "";
                    else if (p[0] === "USER" && p[1]) list.push({ name: p[1], face: p[2] || "" });
                }
                shell.users = list;
                const first = list.find(u => u.name === last) || list[0];
                if (first && !gate.user) { gate.user = first.name; gate.face = first.face; }
            }
        }
    }

    // sessions: the installer's quiet entry wins while it is there (it wraps the
    // uwsm session and keeps its output in a log -- ./install.sh --quiet-boot);
    // otherwise the uwsm Hyprland entry wins (it is the session this machine
    // already runs), otherwise the first Hyprland entry, otherwise the first
    // entry there is
    Process {
        running: true
        command: ["sh", "-c",
            "for f in /usr/share/wayland-sessions/*.desktop; do\n" +
            "  [ -r \"$f\" ] || continue\n" +
            "  printf '===\\t%s\\n' \"$f\"\n" +
            "  cat \"$f\"\n" +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const entries = [];
                let cur = null, inEntry = false;
                for (const raw of text.split("\n")) {
                    if (raw.startsWith("===\t")) {
                        cur = { file: raw.slice(4).split("/").pop(), name: "", exec: "", nodisplay: false };
                        entries.push(cur);
                        inEntry = false;
                        continue;
                    }
                    if (!cur) continue;
                    const line = raw.trim();
                    if (line.startsWith("[")) { inEntry = line === "[Desktop Entry]"; continue; }
                    if (!inEntry) continue;
                    const eq = line.indexOf("=");
                    if (eq < 0) continue;
                    const k = line.slice(0, eq), v = line.slice(eq + 1);
                    if (k === "Name") cur.name = v;
                    else if (k === "Exec") cur.exec = v;
                    else if (k === "NoDisplay") cur.nodisplay = v === "true";
                }
                const usable = entries.filter(e => e.exec && !e.nodisplay);
                const pick = usable.find(e => e.file === "galaga.desktop")
                          || usable.find(e => /uwsm/i.test(e.exec) && /hyprland/i.test(e.name + " " + e.exec))
                          || usable.find(e => /hyprland/i.test(e.name))
                          || usable[0];
                if (pick) shell.sessionCmd = shell.tokenize(pick.exec);
            }
        }
    }

    // the Exec line of a .desktop file -> an argv list for Greetd.launch:
    // quotes and backslashes honoured, field codes (%u, %U, ...) dropped
    function tokenize(exec) {
        const out = [];
        let cur = "", quote = "", esc = false;
        for (let i = 0; i < exec.length; i++) {
            const ch = exec[i];
            if (esc) { cur += ch; esc = false; }
            else if (ch === "\\") esc = true;
            else if (quote) { if (ch === quote) quote = ""; else cur += ch; }
            else if (ch === "\"" || ch === "'") quote = ch;
            else if (ch === " " || ch === "\t") { if (cur) { out.push(cur); cur = ""; } }
            else cur += ch;
        }
        if (cur) out.push(cur);
        return out.filter(t => !/^%[a-zA-Z]$/.test(t));
    }

    // remember the pick for the next boot (in the greeter user's own state dir)
    function remember(name) {
        Quickshell.execDetached(["sh", "-c",
            "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/galaga-greeter\"; mkdir -p \"$d\"; printf %s \"$1\" > \"$d/last-user\"",
            "galaga-greeter", name]);
    }

    // the face's contract, fed by greetd instead of PAM:
    // busy -- a greetd round-trip is in flight; fail -- greetd said no; leaving -- accepted, face plays its exit
    QtObject {
        id: gate
        property string buffer: ""
        property bool fail: false
        property string msg: "" // what pam itself said (faillock's lockout, say) -- the face shows it over its own text
        property bool leaving: false
        property bool busy: false
        property string user: ""
        property string face: ""
        property bool live: false // a greetd session exists (created, PAM conversation open)

        function submit() {
            if (!buffer || busy || leaving || !user) return;
            fail = false;
            msg = "";
            busy = true;
            // the password stays in buffer (the face counts its dots) and is answered
            // to greetd's prompt when it arrives in onAuthMessage
            if (live) Greetd.respond(buffer);
            else Greetd.createSession(user);
        }

        // bubble pick: any in-flight auth dies, the field clears, auth starts over for the new user
        function pick(name) {
            if (!name || name === user) return;
            if (live) Greetd.cancelSession();
            live = false;
            busy = false;
            fail = false;
            msg = "";
            leaving = false;
            buffer = "";
            user = name;
            const u = shell.users.find(x => x.name === name);
            face = u ? u.face : "";
        }
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            // password-only flow: answer the prompts that want the password, ignore the rest
            // (info texts, recoverable errors like a misread fingerprint -- the face has no place for them);
            // an error text is kept: faillock's lockout notice arrives this way and beats a generic "wrong"
            if (error && message) gate.msg = message;
            if (responseRequired) { gate.live = true; Greetd.respond(gate.buffer); }
        }
        function onAuthFailure(message) {
            gate.live = false;
            gate.busy = false;
            gate.buffer = "";
            if (message) gate.msg = message; // pam's own words (a faillock lockout) over the generic failure
            gate.fail = true; // the face shakes and goes red, as on the lock
        }
        function onError(error) {
            if (gate.leaving) return;
            gate.live = false;
            gate.busy = false;
            gate.buffer = "";
            gate.fail = true;
        }
        function onReadyToLaunch() {
            gate.live = false;
            gate.busy = false;
            gate.leaving = true; // the face exits first -- launch() ends this process
            shell.remember(gate.user);
            launchT.start();
        }
    }
    Timer { id: launchT; interval: 470; onTriggered: Greetd.launch(shell.sessionCmd) }

    FloatingWindow {
        id: win
        title: "galaga"
        color: Theme.bg

        LockFace {
            anchors.fill: parent
            auth: gate
            switcher: true
            userName: gate.user
            face: gate.face ? "file://" + gate.face : ""
            // the synced profile photo (install.sh --greeter copies ~/.face to
            // /etc/greetd/faces/<user>, the one place this user can always read):
            // shown as the photo; any other face source keeps the dotted rendering
            photo: gate.face.startsWith("/etc/greetd/faces/") ? "file://" + gate.face : ""
            // the lock's own wallpaper, synced by install.sh --greeter; absent -- the face
            // falls back to the desktop wallpaper, as before
            lockWallUrl: "file:///etc/greetd/faces/lockwall"
            users: shell.users.filter(u => u.name !== gate.user)
            onUserPicked: name => gate.pick(name)
        }
    }
}
