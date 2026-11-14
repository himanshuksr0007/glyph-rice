import QtQuick
import qs
import qs.components
import qs.settings

// windows: a desktop with two windows using the live ring values — gaps,
// border, rounding — and what stays on in game mode. Gaps/border/blur/
// shadows go through Theme.apply; motion through Rules.motion.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 22

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "snapping" }
                SetCard {
                    SetToggle { label: "window snapping"; sub: "super + arrow keys snap · super + z opens layouts. off: the arrows move focus again"; on: Theme.state.snap; onFlip: want => Theme.state.snap = want }
                    SetToggle { label: "resize neighbours together"; sub: "drag one snapped window's edge and its neighbour follows"; on: Theme.state.snapLinked; onFlip: want => Theme.state.snapLinked = want }
                    SetToggle { label: "snap assist"; sub: "after snapping, offer the other windows to fill the space"; on: Theme.state.snapAssist; divider: false; onFlip: want => Theme.state.snapAssist = want }
                }
                SetCard {
                    SetRow { label: "super + ← →"; value: "halves" }
                    SetRow { label: "super + ↑"; value: "corners, then maximise" }
                    SetRow { label: "super + ↓"; value: "restore, then minimise" }
                    SetRow { label: "super + z"; value: "layouts" }
                    SetRow { label: "super + shift + drag"; value: "move a window"; divider: false }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "windows" }
                Lb { text: `hyprland · gaps ${gIn.v} / ${gOut.v} · border ${bord.v} · rounding ${rnd.v} · panels ${pan.v} %`; px: 11; color: Theme.mute }
                ScreenMock {
                    id: desk
                    width: 620
                    Repeater {
                        model: 2
                        Rectangle {
                            id: wnd
                            required property int index
                            readonly property real o: gOut.v * desk.k
                            readonly property real l: 78 * Theme.s * desk.k + o // bar 64 + gap 14, in logical px
                            readonly property real w: (desk.width - (at === "top" ? o : l) - o - 2 * gIn.v * desk.k) / 2
                            readonly property string at: Theme.state.barAt
                            x: (at !== "top" ? l : o) + (index ? w + 2 * gIn.v * desk.k : 0)
                            y: at === "top" ? l : o
                            width: w
                            height: desk.height - (at === "top" ? l : o) - o
                            radius: rnd.v * desk.k
                            color: Theme.s1
                            border { width: bord.v ? Math.max(1, bord.v * desk.k) : 0; color: index ? Theme.s3 : Theme.fg }
                            Behavior on x { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on y { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on width { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on height { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

                            Column {
                                x: 20
                                y: 20
                                spacing: 9
                                Lb { text: wnd.index ? "zen" : "kitty"; px: 10; color: wnd.index ? Theme.mute : Theme.grey }
                                Repeater {
                                    model: [0.7, 0.45, 0.85, 0.3, 0.6, 0.5]
                                    Rectangle {
                                        required property real modelData
                                        width: (wnd.width - 40) * modelData
                                        height: 5
                                        radius: 2.5
                                        color: Theme.s3
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "spacing" }
                Row {
                    spacing: 24
                    Dial { id: gIn; size: 132; label: "gaps in"; to: 30; value: Rules.store.gapsIn; onMoved: v => { Rules.store.gapsIn = v; Theme.apply(); } }
                    Dial { id: gOut; size: 132; label: "gaps out"; to: 60; value: Rules.store.gapsOut; onMoved: v => { Rules.store.gapsOut = v; Theme.apply(); } }
                    Dial { id: bord; size: 132; label: "border"; to: 6; n: 24; value: Rules.store.border; onMoved: v => { Rules.store.border = v; Theme.apply(); } }
                    Dial { id: rnd; size: 132; label: "rounding"; to: 40; value: Theme.state.rounding; onMoved: v => Theme.state.rounding = v } // shell.qml calls Theme.apply itself
                    Dial { id: pan; size: 132; label: "panels"; to: 100; step: 5; value: Theme.state.corners; onMoved: v => Theme.state.corners = v } // the shell's corners, %
                }
            }

            // blur and shadows are not visible in the mockup (flat black) -- toggles only
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "effects" }
                SetCard {
                    SetToggle { label: "blur"; on: Rules.store.blur; onFlip: want => { Rules.store.blur = want; Theme.apply(); } }
                    SetToggle { label: "shadow"; on: Rules.store.shadow; onFlip: want => { Rules.store.shadow = want; Theme.apply(); } }
                    SetToggle { label: "motion"; on: Rules.store.motion; divider: false; onFlip: want => { Rules.store.motion = want; Rules.motion(); } }
                }
            }

            // what stays on in game mode. Off -- game mode drops it; dnd -- only
            // auto game mode (services/Game) sets it. Tearing is always on in
            // game mode
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "in a game" }
                SetCard {
                    SetToggle { label: "gaps"; on: Rules.store.gameGaps; onFlip: want => { Rules.store.gameGaps = want; Theme.apply(); } }
                    SetToggle { label: "motion"; on: Rules.store.gameMotion; onFlip: want => { Rules.store.gameMotion = want; Rules.motion(); } }
                    SetToggle { label: "blur"; on: Rules.store.gameBlur; onFlip: want => { Rules.store.gameBlur = want; Theme.apply(); } }
                    SetToggle { label: "shadow"; on: Rules.store.gameShadow; onFlip: want => { Rules.store.gameShadow = want; Theme.apply(); } }
                    SetToggle { label: "dnd"; on: Rules.store.gameDnd; divider: false; onFlip: want => Rules.store.gameDnd = want }
                }
            }
        }
    }
}
