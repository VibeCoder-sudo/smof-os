import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// lock screen and login: a full screen overlay on every output
ShellRoot {
    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "smof-greeter"
        color: "#0f0d16"
        // the live image asks first: try Smof or install it. The choice is remembered in /tmp for this boot.
        FileView { id: liveF; path: "/var/lib/smof/live"; printErrors: false; blockLoading: true }
        FileView { id: seenF; path: "/tmp/smof-welcome-seen"; printErrors: false; blockLoading: true; watchChanges: true; onFileChanged: reload() }
        readonly property bool askFirst: liveF.text() !== "" && seenF.text() === ""
        Greeter { anchors.fill: parent }
        Welcome { anchors.fill: parent; visible: win.askFirst; z: 5; onTryIt: { seenF.setText("1"); seenF.reload() } }
    }
}
