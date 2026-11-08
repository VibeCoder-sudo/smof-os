import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// Smof desktop shell v1: wallpaper that fades in from the dark start colour, top bar and dock
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "smof-wallpaper"
        color: "#0f0d16"
        Item {
            anchors.fill: parent
            opacity: Ui.entered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 1000; easing.type: Easing.InOutQuad } }
            Item {
                width: 1440; height: 1024; anchors.centerIn: parent
                scale: Math.max(parent.width / 1440, parent.height / 1024)
                Wallpaper { x: -62; y: -60; depth: 2 }
            }
        }
    }

    // software brightness: a dark veil over everything, clicks go through
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-dimmer"
        color: "transparent"
        visible: Ui.brightness < 0.999
        mask: Region {}
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 1 - Ui.brightness }
    }

    // a click on the empty desktop closes open menus and the panel, so does bringing any window forward
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "smof-dismiss"
        color: "transparent"
        visible: Ui.panelOpen || Ui.menuOpen
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: Ui.closeAll() }
    }
    Connections { target: ToplevelManager; function onActiveToplevelChanged() { Ui.closeAll() } }

    IpcHandler { target: "ui"; function panel(): void { Ui.togglePanel() } function close(): void { Ui.closeAll() } function settings(page: string): void { Ui.openSettings(page) } function launcher(): void { Ui.launcherOpen = !Ui.launcherOpen } }

    Settings {}
    AppLauncher {}
    TopBar {}
    Dock {}
    Toasts {}
}
