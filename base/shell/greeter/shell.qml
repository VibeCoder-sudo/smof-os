import Quickshell
import Quickshell.Wayland
import QtQuick

// lock screen and login: a full screen overlay on every output
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "smof-greeter"
        color: "#0f0d16"
        Greeter { anchors.fill: parent }
    }
}
