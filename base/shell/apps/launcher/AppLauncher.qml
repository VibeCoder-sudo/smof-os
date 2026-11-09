import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// app list: opens from the grid tile in the dock. Smof's own apps first, then everything with a .desktop entry. Type to search.
PanelWindow {
    id: lw
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "smof-launcher"
    WlrLayershell.keyboardFocus: lw.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    visible: lw.open || root.opacity > 0.01

    function home(cmd) { Quickshell.execDetached({ command: cmd, workingDirectory: Quickshell.env("HOME") }) }
    property bool open: false
    function close() { lw.open = false }

    readonly property var builtins: [
        { id: "@foot", name: "Terminal", icon: "foot", run: function () { lw.home(["foot"]) } },
        { id: "@files", name: "Files", icon: "system-file-manager", run: function () { Ui.run(["/usr/local/bin/smof-files"]) } },
        { id: "@store", name: "Smof Store", icon: "org.gnome.Software", run: function () { Ui.run(["/usr/local/bin/smof-store"]) } },
        { id: "@upscaler", name: "Upscaler", icon: "applications-graphics", run: function () { lw.home(["/usr/local/bin/smof-upscaler"]) } },
        { id: "@settings", name: "Settings", icon: "preferences-system", run: function () { Ui.openSettings() } }
    ]
    readonly property var hidden: ["foot", "foot client", "foot server", "quickshell"]

    // the list shown: built in apps and desktop entries, filtered by the search text
    readonly property var items: {
        var q = search.text.trim().toLowerCase()
        var out = []
        var b = lw.builtins
        for (var i = 0; i < b.length; i++) if (q === "" || b[i].name.toLowerCase().indexOf(q) >= 0) out.push(b[i])
        var rest = []
        var ds = DesktopEntries.applications.values
        for (var k = 0; k < ds.length; k++) {
            var e = ds[k]
            if (e.noDisplay) continue
            var n = (e.name || "")
            if (n === "" || lw.hidden.indexOf(n.toLowerCase()) >= 0) continue
            if (q !== "" && n.toLowerCase().indexOf(q) < 0 && (e.genericName || "").toLowerCase().indexOf(q) < 0) continue
            rest.push({ name: n, icon: e.icon, entry: e })
        }
        rest.sort(function (a, c) { return a.name.localeCompare(c.name) })
        return out.concat(rest)
    }
    // apps kept in the dock, the dock owns the file and this only reads it
    property var pins: ["@foot", "@launcher", "@store", "@settings", "@files"]
    FileView {
        path: Quickshell.env("HOME") + "/.config/smof-dock.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { var o = JSON.parse(text()); lw.pins = Array.isArray(o) ? ["@foot", "@launcher", "@store", "@settings", "@files"].concat(o) : (o && o.items ? o.items : lw.pins) } catch (e) {} }
    }
    function launchItem(it) {
        if (!it) return
        lw.close()
        if (it.run) { it.run(); return }
        if (!it.entry) return
        // apps start with the accessibility switches on, so their menus can show in the top bar
        var cmd = it.entry.command
        if (cmd && cmd.length > 0 && !it.entry.runInTerminal)
            Quickshell.execDetached({ command: ["env", "QT_ACCESSIBILITY=1", "QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1", "GTK_A11Y=atspi"].concat(cmd), workingDirectory: it.entry.workingDirectory || Quickshell.env("HOME") })
        else it.entry.execute()
    }

    // ---- search that understands meaning: smof-spotlight keeps running and answers one line per query ----
    property bool spotOn: false
    property var spotAnswer: ""
    property var spotHits: []
    property string spotQ: ""
    Process {
        id: spotP
        command: ["/usr/local/bin/smof-spotlight", "serve"]
        running: lw.spotOn
        stdinEnabled: true
        stdout: SplitParser { onRead: (line) => { try { var o = JSON.parse(line); if (o.q === lw.spotQ) { lw.spotAnswer = o.answer; lw.spotHits = o.hits } } catch (e) {} } }
    }
    Timer { id: spotT; interval: 140; onTriggered: { var q = search.text.trim(); lw.spotQ = q; if (q.length > 0 && spotP.running) spotP.write(JSON.stringify({ q: q }) + "\n"); else { lw.spotAnswer = ""; lw.spotHits = [] } } }
    // what the list shows for a typed text: the answer, apps matched by name, then the hits of the meaning search
    readonly property var results: {
        var out = []
        if (lw.spotAnswer !== "" && lw.spotQ === search.text.trim()) out.push({ kind: "answer", name: lw.spotAnswer, sub: "Answer, press Return to copy" })
        var seen = {}
        for (var i = 0; i < lw.items.length && out.length < 7; i++) { var it = lw.items[i]; out.push({ kind: "app", name: it.name, sub: "App", icon: it.icon, app: it }); seen[it.name] = true }
        if (lw.spotQ === search.text.trim()) for (var j = 0; j < lw.spotHits.length; j++) {
            var h = lw.spotHits[j]
            if (h.kind === "app" && seen[h.name]) continue
            var sub = h.kind === "file" ? h.id.replace(Quickshell.env("HOME"), "~") : (h.kind === "clip" ? "Clipboard" : (h.kind === "setting" ? "Settings" : (h.kind === "action" ? "Action" : "App")))
            out.push({ kind: h.kind, name: h.name, sub: sub, icon: h.icon, id: h.id, cmd: h.cmd }); seen[h.name] = true
        }
        return out
    }
    function openResult(r) {
        if (!r) return
        lw.close()
        if (r.kind === "app" && r.app) { lw.launchItem(r.app); return }
        if (r.kind === "app") { var ds = DesktopEntries.applications.values; for (var k = 0; k < ds.length; k++) if (ds[k].id === r.id) { lw.launchItem({ entry: ds[k] }); return } return }
        if (r.kind === "setting" || r.kind === "action") Quickshell.execDetached(r.cmd)
        else if (r.kind === "file") Quickshell.execDetached(["xdg-open", r.id])
        else if (r.kind === "clip") Quickshell.execDetached(["sh", "-c", "cliphist decode " + r.id + " | wl-copy"])
        else if (r.kind === "answer") Quickshell.execDetached(["wl-copy", r.name.split(" ")[0]])
    }

    onVisibleChanged: if (visible && lw.open) { search.text = ""; search.forceActiveFocus() }
    onOpenChanged: if (open) { lw.spotOn = true; search.text = ""; search.forceActiveFocus() }

    Item {
        id: root
        anchors.fill: parent
        opacity: lw.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        focus: true
        Keys.onEscapePressed: lw.close()

        // dim backdrop, a click on it closes
        Rectangle { anchors.fill: parent; color: Theme.dark ? "#000000" : "#FFFFFF"; opacity: Theme.dark ? .38 : .30 }
        MouseArea { anchors.fill: parent; onClicked: lw.close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(1020, parent.width - 160)
            height: Math.min(700, parent.height - 220)
            radius: 36
            color: Theme.panelbg
            border.color: Theme.glassBorder
            scale: lw.open ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }   // clicks inside do not close

            // search
            Rectangle {
                id: sbox
                x: 28; y: 28; width: parent.width - 56; height: 52; radius: 26
                color: Theme.glass2
                T { visible: search.text === ""; x: 52; anchors.verticalCenter: parent.verticalCenter; text: "Search apps, files, or ask a question"; font.pixelSize: 18; color: Theme.i5 }
                Image { x: 18; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sourceSize: Qt.size(60, 60); opacity: .7
                    source: "file:///usr/share/smof/icons/grid" + Theme.sfx + ".svg" }
                TextInput {
                    id: search
                    x: 52; width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                    font.family: "Google Sans Flex"; font.pixelSize: 18; color: Theme.ink
                    clip: true
                    selectByMouse: true
                    Keys.onEscapePressed: lw.close()
                    Keys.onReturnPressed: { if (search.text.trim() === "") lw.launchItem(lw.items[0]); else lw.openResult(lw.results[Math.max(0, rlist.currentIndex)]) }
                    Keys.onDownPressed: rlist.currentIndex = Math.min(rlist.count - 1, rlist.currentIndex + 1)
                    Keys.onUpPressed: rlist.currentIndex = Math.max(0, rlist.currentIndex - 1)
                    onTextChanged: { grid.positionViewAtBeginning(); rlist.currentIndex = 0; spotT.restart() }
                }
            }

            // typed text: results of apps, files, clipboard and answers
            ListView {
                SmoothWheel {}
                id: rlist
                visible: search.text.trim() !== ""
                x: 20; y: 100
                width: parent.width - 40; height: parent.height - 120
                clip: true; spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: lw.results
                currentIndex: 0
                delegate: Item {
                    id: rr
                    required property var modelData
                    required property int index
                    width: rlist.width; height: modelData.kind === "answer" ? 84 : 58
                    Rectangle { anchors.fill: parent; radius: 18; color: Theme.acc; opacity: rma.containsMouse ? .14 : (rr.index === rlist.currentIndex ? .10 : 0) }
                    Item { x: 14; y: (rr.height - 38) / 2; width: 38; height: 38
                        Image { id: ri; anchors.fill: parent; visible: status === Image.Ready && rr.modelData.kind === "app"
                            source: rr.modelData.kind !== "app" || !rr.modelData.icon ? "" : (rr.modelData.icon.charAt(0) === "/" ? "file://" + rr.modelData.icon : "file:///usr/share/icons/Papirus/64x64/apps/" + rr.modelData.icon + ".svg")
                            sourceSize: Qt.size(76, 76); fillMode: Image.PreserveAspectFit; smooth: true }
                        Rectangle { visible: !ri.visible; anchors.fill: parent; radius: 12; color: rr.modelData.kind === "file" ? Theme.pxbg : (rr.modelData.kind === "answer" ? Theme.acc : (rr.modelData.kind === "setting" ? Theme.sysbg : Theme.moonbg))
                            T { anchors.centerIn: parent; text: rr.modelData.kind === "file" ? "F" : (rr.modelData.kind === "clip" ? "C" : (rr.modelData.kind === "answer" ? "=" : (rr.modelData.kind === "setting" ? "S" : (rr.modelData.kind === "action" ? ">" : (rr.modelData.name || "?").charAt(0).toUpperCase())))); w: 600; font.pixelSize: 18; color: rr.modelData.kind === "answer" ? Theme.onacc : Theme.acc } }
                    }
                    Column { x: 68; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 90; spacing: 2
                        T { text: rr.modelData.name; font.pixelSize: rr.modelData.kind === "answer" ? 30 : 17; w: rr.modelData.kind === "answer" ? 640 : 520; elide: Text.ElideRight; width: parent.width; maximumLineCount: 1 }
                        T { text: rr.modelData.sub; font.pixelSize: 13; color: Theme.i55; elide: Text.ElideMiddle; width: parent.width; maximumLineCount: 1 } }
                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; onClicked: lw.openResult(rr.modelData) }
                }
            }

            GridView {

                SmoothWheel {}
                id: grid
                visible: search.text.trim() === ""
                x: 20; y: 100
                width: parent.width - 40; height: parent.height - 120
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 150)))
                cellHeight: 150
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: lw.items
                delegate: Item {
                    id: tile
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    readonly property string path: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                    Rectangle { anchors.fill: parent; anchors.margins: 6; radius: 24; color: Theme.acc; opacity: tma.pressed ? .2 : (tma.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 100 } } }
                    Item {
                        x: (parent.width - 72) / 2; y: 18; width: 72; height: 72
                        // the Papirus icon first, then whatever the system theme has, and a letter when nothing fits
                        Image { id: pimg; anchors.fill: parent; visible: status === Image.Ready
                            source: !modelData.icon ? "" : (modelData.icon.charAt(0) === "/" ? "file://" + modelData.icon : "file:///usr/share/icons/Papirus/64x64/apps/" + modelData.icon + ".svg")
                            sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectFit; smooth: true }
                        Image { visible: pimg.status !== Image.Ready && tile.path !== "" && status === Image.Ready; anchors.fill: parent; source: pimg.status === Image.Error ? tile.path : ""; sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectFit; smooth: true }
                        Rectangle {
                            visible: pimg.status !== Image.Ready && !(tile.path !== "" && pimg.status === Image.Error)
                            anchors.fill: parent; radius: 24
                            color: modelData.glyph === "sliders" ? Theme.sysbg : (modelData.glyph === "dockfolder" ? Theme.yelbg : (modelData.glyph === "folder" ? Theme.pxbg : Theme.moonbg))
                            Image { visible: !!modelData.glyph; anchors.centerIn: parent; width: 34; height: 34; sourceSize: Qt.size(102, 102); source: modelData.glyph ? "file:///usr/share/smof/icons/" + modelData.glyph + Theme.sfx + ".svg" : "" }
                            T { visible: !modelData.glyph; anchors.centerIn: parent; text: (modelData.name || "?").charAt(0).toUpperCase(); w: 600; font.pixelSize: 30; color: Theme.acc }
                        }
                    }
                    T { x: 10; y: 100; width: parent.width - 20; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.pixelSize: 15; elide: Text.ElideRight; maximumLineCount: 1 }
                    MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => { if (m.button === Qt.RightButton && tile.pid !== "") tile.togglePin(); else lw.launchItem(modelData) } }
                    // a small pill on hover: keep the app in the dock, or take it out again
                    readonly property string pid: modelData.id ? modelData.id : (modelData.entry ? modelData.entry.id : "")
                    readonly property bool pinned: pid !== "" && lw.pins.indexOf(pid) >= 0
                    function togglePin() { if (pid !== "") Quickshell.execDetached(["/usr/local/bin/smof-ipc", "dock", "dock", pinned ? "unpin" : "pin", pid]) }
                    Rectangle {
                        visible: tile.pid !== "" && (tma.containsMouse || pma.containsMouse || tile.pinned)
                        opacity: (tma.containsMouse || pma.containsMouse) ? 1 : .8
                        anchors.horizontalCenter: parent.horizontalCenter; y: 6
                        width: pt.implicitWidth + 20; height: 26; radius: 13
                        color: tile.pinned ? Theme.acc : Theme.moonbg
                        T { id: pt; anchors.centerIn: parent; text: tile.pinned ? "In dock" : "Keep in dock"; w: 560; font.pixelSize: 12; color: tile.pinned ? Theme.onacc : Theme.acc }
                        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: tile.togglePin() }
                    }
                }
                T { visible: lw.items.length === 0; anchors.centerIn: parent; text: "No apps match"; font.pixelSize: 18; color: Theme.i55 }
            }
        }
    }
}
