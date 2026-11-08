import Quickshell
import Quickshell.Io
import QtQuick

// Smof permission prompt, a separate app: the popup that asks for the password when something wants administrator
// rights, from sudo in a terminal or from any app through polkit. Looks like a UAC prompt, dims the screen.
ShellRoot {
    Auth { id: auth }
    IpcHandler { target: "auth"
        function ask(fifo: string, cmd: string, retry: string, user: string): void { auth.addSudo(fifo, cmd, retry === "1", user) }
        function cancel(fifo: string): void { auth.dropSudo(fifo) } }
}
