import Quickshell
import Quickshell.Io
import QtQuick

// Smof Store: apps and tools from pacman, Homebrew and the AUR in one place. A separate app.
ShellRoot {
    Store { id: store }
    IpcHandler { target: "store"
        function openApp(source: string, name: string): void { store.viewKey = source + ":" + name }
        function install(source: string, name: string): void { store.enqueue(source, "install", name) }
        function goto(page: string): void { store.viewKey = ""; store.page = page }
        function search(q: string): void { store.setQuery(q) }
        function log(): void { store.logOpen = true } }
}
