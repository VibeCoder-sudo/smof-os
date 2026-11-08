import Quickshell
import Quickshell.Io
import QtQuick

// Smof Upscaler: pictures go into a queue, a small neural network makes them bigger, a slider compares before and after.
ShellRoot {
    Upscaler { id: up }
    IpcHandler { target: "upscaler"
        function add(paths: string): void { up.addPaths(paths.split("|").filter(function (p) { return p !== "" && up.isPic(p) })) } }
}
