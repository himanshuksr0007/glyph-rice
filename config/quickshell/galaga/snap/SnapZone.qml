import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

// the drag-snap preview (services/Snap's drag tracker): while a window is
// being dragged and the cursor sits on an edge or a corner, this draws the
// zone the window will take if it is let go there -- a translucent panel in
// shell colours over the desktop. The mask is empty on purpose: the preview
// never eats a click, and it takes no keyboard focus; it only renders the
// tracker's zone.
PanelWindow {
    id: root

    readonly property bool shown: Snap.dragZone !== "" && Snap.dragRect !== null
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: 130 } }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "galaga-snapzone"
    mask: Region { } // no region anywhere: the preview never eats a click

    Rectangle {
        // the zone rect is in global coordinates; this window's screen starts
        // at its own corner of the desktop, so draw relative to it
        readonly property var zr: Snap.dragRect
        x: zr ? zr.x - (root.screen?.x ?? 0) : 0
        y: zr ? zr.y - (root.screen?.y ?? 0) : 0
        width: zr ? zr.w : 0
        height: zr ? zr.h : 0
        radius: Theme.corner(16)
        color: Theme.fade(Theme.fg, 0.14)
        border { width: 2; color: Theme.fade(Theme.fg, 0.5) }
        opacity: root.t
    }
}
