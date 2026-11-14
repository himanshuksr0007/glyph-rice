import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// snap layouts and snap assist (services/Snap): Super+Z opens the layouts --
// six shapes drawn as little maps, the focused window takes the first space.
// Picking one (or snapping with the arrows, when the rest of the shape is
// empty) turns the popup into the assist picker: the other windows on the
// desktop, numbered, one click per remaining space. Esc stops early -- what
// is placed stays placed, in its group. The popup only renders Snap's state;
// every decision lives in the service.
PanelWindow {
    id: root

    readonly property bool shown: Snap.popOpen
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "galaga-snap"

    Rectangle {
        anchors.fill: parent
        color: Theme.fade(Theme.bg, 0.82)
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: Snap.popCancel() }
    }

    Stage {
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { Snap.popCancel(); e.accepted = true; return; }
            const n = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5, Qt.Key_6].indexOf(e.key);
            if (n < 0) return;
            if (Snap.popMode === "layouts") Snap.chooseLayout(n);
            else if (Snap.popMode === "assist") { const c = Snap.assistCands[n]; if (c) Snap.chooseAssist(c.addr); }
            else return;
            e.accepted = true;
        }

        Rectangle {
            anchors.centerIn: parent
            width: card.width + 56
            height: card.height + 52
            radius: Theme.corner(22)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            opacity: root.t
            transform: Translate { y: 16 * (1 - root.t) }

            Column {
                id: card
                anchors.centerIn: parent
                spacing: 18

                Row {
                    spacing: 14
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10; radius: 5
                        color: Theme.red
                    }
                    Num { text: Snap.popMode === "assist" ? "SNAP NEXT" : "SNAP LAYOUTS"; font.pixelSize: 30 }
                }
                Lb {
                    visible: Snap.popMode === "assist"
                    text: "fill the " + (Snap.assistZones[0]?.label ?? "") + (Snap.assistZones.length > 1 ? ` · ${Snap.assistZones.length} spaces left` : "")
                    px: 11
                    color: Theme.mute
                }

                // the six layouts as little maps: space 1 solid, the rest grey
                Grid {
                    visible: Snap.popMode === "layouts"
                    columns: 3
                    spacing: 14
                    Repeater {
                        model: Snap.layouts
                        Item {
                            id: lay
                            required property var modelData
                            required property int index
                            width: 152
                            height: 116

                            Rectangle {
                                id: frame
                                width: parent.width
                                height: 88
                                radius: Theme.corner(12)
                                color: Theme.s2
                                border { width: 1; color: hov.hovered ? Theme.fg : Theme.s3 }
                                Repeater {
                                    model: lay.modelData.zones
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        x: 6 + modelData.f[0] * (frame.width - 12) + (modelData.f[0] > 0 ? 1 : 0)
                                        y: 6 + modelData.f[1] * (frame.height - 12) + (modelData.f[1] > 0 ? 1 : 0)
                                        width: modelData.f[2] * (frame.width - 12) - (modelData.f[0] > 0 || modelData.f[0] + modelData.f[2] < 1 ? 2 : 0)
                                        height: modelData.f[3] * (frame.height - 12) - (modelData.f[1] > 0 || modelData.f[1] + modelData.f[3] < 1 ? 2 : 0)
                                        radius: 3
                                        color: index === 0 ? Theme.fg : Theme.s3
                                    }
                                }
                                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Snap.chooseLayout(lay.index)
                                }
                            }
                            Row {
                                y: 96
                                spacing: 8
                                Lb { text: `${lay.index + 1}`; px: 11; color: hov.hovered ? Theme.red : Theme.mute }
                                Lb { text: lay.modelData.name; px: 11; color: Theme.fg }
                            }
                        }
                    }
                }

                // assist: the desktop's other windows, one per remaining space
                Column {
                    visible: Snap.popMode === "assist"
                    spacing: 4
                    Repeater {
                        model: Snap.assistCands
                        Item {
                            id: cand
                            required property var modelData
                            required property int index
                            width: 400
                            height: 46

                            Rectangle {
                                anchors { fill: parent; leftMargin: -8; rightMargin: -8 }
                                radius: Theme.corner(12)
                                color: Theme.s2
                                opacity: chov.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }
                            Row {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                spacing: 12
                                Lb { anchors.verticalCenter: parent.verticalCenter; text: `${cand.index + 1}`; px: 11; color: chov.hovered ? Theme.red : Theme.mute }
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22; height: 22
                                    sourceSize { width: 22; height: 22 }
                                    source: { const ic = DesktopEntries.heuristicLookup(cand.modelData.cls)?.icon; return ic ? Quickshell.iconPath(ic, true) : ""; }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: cand.modelData.title
                                        font { family: Theme.ui; pixelSize: 14 }
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                        width: 320
                                    }
                                    Lb { text: DesktopEntries.heuristicLookup(cand.modelData.cls)?.name ?? cand.modelData.cls; px: 10; color: Theme.mute }
                                }
                            }
                            HoverHandler { id: chov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: Snap.chooseAssist(cand.modelData.addr)
                            }
                        }
                    }
                }
            }
        }
    }
}
