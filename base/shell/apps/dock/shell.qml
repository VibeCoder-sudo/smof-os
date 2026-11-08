import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// Smof dock: launchers and the open windows
ShellRoot {
    // a click on the empty desktop closes the open menus and the panel, so does bringing any window forward
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "smof-dismiss"
        color: "transparent"
        visible: Ui.panelOpen || Ui.menuOpen
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: { Ui.closeAll(); Ui.closeOther("bar") } }
    }
    Connections { target: ToplevelManager; function onActiveToplevelChanged() { Ui.closeAll() } }

    IpcHandler { target: "ui"; function close(): void { Ui.closeAll() } }

    Dock {}
}
