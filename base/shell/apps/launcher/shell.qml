import Quickshell
import Quickshell.Io
import QtQuick

// Smof app list: opens over the desktop, search by typing
ShellRoot {
    AppLauncher { id: launcher }
    IpcHandler { target: "launcher"
        function toggle(): void { launcher.open = !launcher.open }
        function open(): void { launcher.open = true }
        function hide(): void { launcher.open = false } }
}
