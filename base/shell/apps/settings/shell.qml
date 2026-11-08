import Quickshell
import Quickshell.Io
import QtQuick

// Smof Settings, a separate app: its own process and window. Closing the window ends the app.
ShellRoot {
    Settings { id: settings }
    IpcHandler { target: "settings"; function page(name: string): void { if (name !== "") settings.page = name } }
}
