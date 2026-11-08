import Quickshell
import Quickshell.Io
import QtQuick

// Smof Files, a separate app: its own process and window. Closing the window ends the app.
ShellRoot {
    Files { id: files }
    IpcHandler { target: "files"; function goto(path: string): void { if (path !== "") files.go(path) }
        function drop(dest: string, paths: string, mode: string): void { files.op([mode, dest].concat(paths.split("|"))) }
        function ctx(name: string): void { var it = null; for (var i = 0; i < files.items.length; i++) if (files.items[i].name === name) it = files.items[i]; if (it && !files.isSel(name)) files.setSel([name], name); files.openCtx(300, 200, it) }
        function up(path: string, scale: int, mode: string): void { files.upscale(path, scale, mode) }
        function view(name: string): void { files.viewing = name }
        function admin(): void { files.goAdmin() }
        function emptyTrash(): void { files.go(Quickshell.env("HOME") + "/.local/share/Trash/files"); files.askEmpty() }
        function drive(dev: string): void { for (var i = 0; i < files.drives.length; i++) if (files.drives[i].dev === dev) files.openDrive(files.drives[i]) } }
}
