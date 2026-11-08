import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects

// floating dock: launchers on the left, open windows on the right. Click a window to bring it back, click the active one to minimize it.
PanelWindow {
    id: dock
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 120
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "smof-dock"
    color: "transparent"
    mask: Region { item: pill }

    function tintColor(t) { return Theme.moonbg }
    // ---- the dock: one list the user orders. "@name" are Smof's own apps, the rest are desktop entry ids ----
    // saved in ~/.config/smof-dock.json as {"v":2,"items":[...]}; the old format was a plain list of ids
    readonly property var defaults: ["@foot", "@launcher", "@store", "@settings", "@files"]
    property var order: defaults
    // reading the list keeps the desktop entries loaded, so a launcher dropped on the dock can be matched at once
    readonly property int entryCount: DesktopEntries.applications.values.length
    FileView {
        id: pinF
        path: Quickshell.env("HOME") + "/.config/smof-dock.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var o = JSON.parse(text()), l = null
                if (Array.isArray(o)) l = dock.defaults.concat(o)
                else if (o && Array.isArray(o.items)) l = o.items
                if (l) { if (l.indexOf("@launcher") < 0) l.splice(Math.min(1, l.length), 0, "@launcher"); dock.order = l }
            } catch (e) {}
        }
    }
    function saveOrder(list) { dock.order = list; pinF.setText(JSON.stringify({ v: 2, items: list })) }
    function pin(id) { if (id !== "" && dock.order.indexOf(id) < 0) saveOrder(dock.order.concat([id])) }
    function unpin(id) { if (id === "@launcher") return; saveOrder(dock.order.filter(function (x) { return x !== id })) }
    function moveItem(from, to) {
        if (from === to || from < 0 || to < 0) return
        var l = dock.order.slice(); var x = l.splice(from, 1)[0]; l.splice(to, 0, x); saveOrder(l)
    }
    readonly property var builtinDefs: ({
        "@foot": { name: "Terminal", icon: "foot" },
        "@launcher": { name: "All apps", icon: "applications-all" },
        "@store": { name: "Smof Store", icon: "org.gnome.Software", title: "Smof Store" },
        "@settings": { name: "Settings", icon: "preferences-system", title: "Settings" },
        "@files": { name: "Files", icon: "system-file-manager", title: "Files" },
        "@upscaler": { name: "Upscaler", icon: "applications-graphics", title: "Upscaler" }
    })
    function builtinRun(key) {
        if (key === "@foot") launch(["foot"])
        else if (key === "@store") Ui.run(["/usr/local/bin/smof-store"])
        else if (key === "@settings") Ui.openSettings()
        else if (key === "@files") Ui.run(["/usr/local/bin/smof-files"])
        else if (key === "@upscaler") Ui.run(["/usr/local/bin/smof-upscaler"])
        else if (key === "@launcher") Ui.toggleLauncher()
    }
    // what is drawn: built in apps and pinned desktop entries, in the user's order
    readonly property var items: {
        var out = []
        for (var i = 0; i < order.length; i++) {
            var k = order[i]
            if (k.charAt(0) === "@") { var d = builtinDefs[k]; if (d) out.push({ key: k, builtin: true, name: d.name, icon: d.icon, title: d.title || "", entry: null }) }
            else {
                var e = DesktopEntries.byId(k) || DesktopEntries.heuristicLookup(k)
                if (e) out.push({ key: k, builtin: false, name: e.name, icon: e.icon || "application-x-executable", title: "", entry: e })
            }
        }
        return out
    }
    function isOurs(tl) { var a = ((tl && tl.appId) || "").toLowerCase(); return a.indexOf("quickshell") >= 0 }
    // which item of the dock a window belongs to, empty when none
    function ownerKey(tl) {
        if (!tl) return ""
        var a = (tl.appId || ""), al = a.toLowerCase()
        var d = a !== "" ? DesktopEntries.heuristicLookup(a) : null
        var its = items
        for (var i = 0; i < its.length; i++) {
            var it = its[i]
            if (it.key === "@launcher") continue
            if (it.key === "@foot") { if (al.indexOf("foot") >= 0) return it.key; continue }
            if (it.builtin) { if (isOurs(tl) && tl.title === it.title) return it.key; continue }
            if (!isOurs(tl) && (it.key.toLowerCase() === al || (d && d.id === it.key))) return it.key
        }
        return ""
    }
    function groupKey(tl) { return isOurs(tl) ? "t:" + tl.title : "a:" + (tl.appId || tl.title) }
    // the key this window would be kept in the dock as
    function keepKeyFor(tl) {
        if (isOurs(tl)) { for (var k in builtinDefs) if (builtinDefs[k].title === tl.title) return k; return "" }
        if ((tl.appId || "").toLowerCase().indexOf("foot") >= 0) return "@foot"
        var d = DesktopEntries.heuristicLookup(tl.appId || "")
        return d ? d.id : ""
    }
    function windowsOf(key) {
        var v = ToplevelManager.toplevels.values, out = []
        for (var i = 0; i < v.length; i++) if (ownerKey(v[i]) === key) out.push(v[i])
        return out
    }
    function windowsInGroup(gk) {
        var v = ToplevelManager.toplevels.values, out = []
        for (var i = 0; i < v.length; i++) if (ownerKey(v[i]) === "" && groupKey(v[i]) === gk) out.push(v[i])
        return out
    }
    // running apps that are not in the dock yet, one tile per app, added after the pinned ones
    readonly property var groups: {
        var v = ToplevelManager.toplevels.values, seen = {}, out = []
        for (var i = 0; i < v.length; i++) {
            if (ownerKey(v[i]) !== "") continue
            var gk = groupKey(v[i])
            if (seen[gk]) continue
            seen[gk] = true
            out.push({ key: gk, name: v[i].title || v[i].appId || "App", icon: iconFor(v[i].appId, v[i].title) })
        }
        return out
    }
    function anyActive(w) { for (var i = 0; i < w.length; i++) if (w[i].activated) return true; return false }
    function launchEntry(e) {
        var cmd = e.command
        if (cmd && cmd.length > 0 && !e.runInTerminal)
            Quickshell.execDetached({ command: ["env", "QT_ACCESSIBILITY=1", "QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1", "GTK_A11Y=atspi"].concat(cmd), workingDirectory: e.workingDirectory || Quickshell.env("HOME") })
        else e.execute()
    }
    // click: start the app, or bring a window forward; a click on the only active window tucks it away
    function cycle(w) {
        for (var i = 0; i < w.length; i++) if (w[i].minimized) { w[i].minimized = false; w[i].activate(); return }
        for (var j = 0; j < w.length; j++) if (!w[j].activated) { w[j].activate(); return }
        if (w.length > 0) w[0].minimized = true
    }
    function clickItem(it, w) {
        if (it.key === "@launcher") { builtinRun(it.key); return }
        if (w.length === 0) { if (it.builtin) builtinRun(it.key); else launchEntry(it.entry); return }
        cycle(w)
    }
    function windowEntries(w) {
        var m = []
        for (var i = 0; i < w.length; i++) { (function (tl) { m.push({ label: (tl.title || "Window"), run: function () { tl.minimized = false; tl.activate() } }) })(w[i]) }
        return m
    }
    function itemMenu(it, w) {
        var m = [ { header: it.name } ]
        if (it.key === "@launcher") m.push({ label: "Show all apps", run: function () { Ui.toggleLauncher() } })
        else m.push({ label: w.length > 0 ? "New window" : "Open", run: function () { if (it.builtin) dock.builtinRun(it.key); else dock.launchEntry(it.entry) } })
        if (w.length > 0) { m.push({ sep: true }); m = m.concat(windowEntries(w)) }
        if (it.key !== "@launcher") { m.push({ sep: true }); m.push({ label: "Remove from dock", run: function () { dock.unpin(it.key) } }) }
        return m
    }
    function groupMenu(g, w) {
        if (w.length === 1) return windowMenu(w[0])
        var m = [ { header: g.name } ]
        m = m.concat(windowEntries(w))
        m.push({ sep: true })
        var k = w.length ? keepKeyFor(w[0]) : ""
        m.push({ label: "Keep in dock", disabled: k === "", run: function () { dock.pin(k) } })
        m.push({ label: "Close all", danger: true, run: function () { for (var i = 0; i < w.length; i++) w[i].close() } })
        return m
    }
    // something let go over the dock from the desktop: spec is {kind, name, exec, paths}, gx and gy are screen coordinates
    function dropAt(specJson, gx, gy) {
        var sp = null
        try { sp = JSON.parse(specJson) } catch (e) { return }
        var scrH = dock.screen ? dock.screen.height : Quickshell.screens[0].height
        var ly = gy - (scrH - dock.height)
        function hit(t) { var r = t.mapToItem(dock.contentItem, 0, 0); return gx >= r.x && gx <= r.x + t.width && ly >= r.y && ly <= r.y + t.height }
        var ps = sp.paths || []
        if (hit(trashTile)) { if (ps.length) { Ui.run(["/usr/local/bin/smof-fileops", "trash"].concat(ps)); trashP.running = true; deskRefreshT.restart() } }
        else if (hit(stackTile)) { if (ps.length) { Ui.run(["/usr/local/bin/smof-fileops", "move", stackDir].concat(ps)); stackRefT.restart(); deskRefreshT.restart() } }
        if (!(hit(trashTile) || hit(stackTile)) && sp.kind === "app" && pill.x <= gx && gx <= pill.x + pill.width && ly >= pill.y) { var k = keyForLauncher(sp); if (k !== "") { pinAt(k, insertIndexAt(gx)); if (ps.length) { Ui.run(["/usr/local/bin/smof-fileops", "trash"].concat(ps)); deskRefreshT.restart() } } }
    }
    Timer { id: deskRefreshT; interval: 900; onTriggered: Quickshell.execDetached(["/usr/local/bin/smof-ipc", "wallpaper", "desktop", "refresh"]) }
    Timer { id: stackRefT; interval: 900; onTriggered: stackP.running = true }
    // the place in the dock a thing dropped at screen x would take
    function insertIndexAt(gx) {
        var n = 0
        for (var i = 0; i < itemRep.count; i++) { var c = itemRep.itemAt(i); if (c && c.mapToItem(dock.contentItem, c.width / 2, 0).x < gx) n++ }
        return n
    }
    function pinAt(id, idx) {
        if (id === "" || order.indexOf(id) >= 0) return
        var l = order.slice(); l.splice(Math.max(0, Math.min(idx, l.length)), 0, id); saveOrder(l)
    }
    // which dock item a desktop launcher stands for: one of ours, or the desktop entry with the same command
    function keyForLauncher(sp) {
        var ex = sp.exec || ""
        if (ex === "foot") return "@foot"
        if (ex.indexOf("smof-store") >= 0) return "@store"
        if (ex.indexOf("smof-settings") >= 0) return "@settings"
        if (ex.indexOf("smof-files") >= 0) return "@files"
        // look the entry up by name first: the list of all entries is filled lazily and may still be empty here
        var base = ex.split(" ")[0].split("/").pop()
        var guesses = [base, sp.name || "", (sp.name || "").toLowerCase()]
        for (var g = 0; g < guesses.length; g++) {
            if (guesses[g] === "") continue
            var found = DesktopEntries.byId(guesses[g]) || DesktopEntries.heuristicLookup(guesses[g])
            if (found && found.id) return found.id
        }
        var ds = DesktopEntries.applications.values
        for (var i = 0; i < ds.length; i++) {
            var e = ds[i], c = (e.command || []).join(" ")
            if ((c !== "" && ex.indexOf(c) === 0) || (e.name === sp.name && e.id)) return e.id
        }
        return ""
    }
    // an app dragged out of the dock becomes an icon on the desktop
    function toDesktop(it, gx, gy) {
        var cmd = []
        if (it.key === "@foot") cmd = ["foot"]
        else if (it.key === "@store") cmd = ["/usr/local/bin/smof-store"]
        else if (it.key === "@settings") cmd = ["/usr/local/bin/smof-settings"]
        else if (it.key === "@files") cmd = ["/usr/local/bin/smof-files"]
        else if (it.key === "@upscaler") cmd = ["/usr/local/bin/smof-upscaler"]
        else if (it.entry && it.entry.command) cmd = it.entry.command
        if (cmd.length === 0) return
        var spec = JSON.stringify({ name: it.name, icon: it.icon, cmd: cmd })
        Quickshell.execDetached(["/usr/local/bin/smof-ipc", "wallpaper", "desktop", "addapp", spec, String(Math.round(gx)), String(Math.round(gy))])
    }
    // ---- the folder tile next to the trash: recent files of one folder, set in Settings ----
    property string stackDir: Quickshell.env("HOME") + "/Downloads"
    property var stackItems: []
    FileView {
        id: stackF
        path: Quickshell.env("HOME") + "/.config/smof-dock-stack.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { var o = JSON.parse(text()); if (o && o.dir) { dock.stackDir = o.dir; stackP.running = true } } catch (e) {} }
    }
    Process {
        id: stackP
        command: ["/usr/local/bin/smof-fileops", "ls", dock.stackDir]
        stdout: StdioCollector { onStreamFinished: { try { var l = JSON.parse(text).items; l.sort(function (a, b) { return b.mtime - a.mtime }); dock.stackItems = l.slice(0, 8) } catch (e) {} } }
    }
    readonly property string stackName: { var n = stackDir.replace(/\/+$/, "").split("/").pop(); return n !== "" ? n : "Home" }
    readonly property string stackIcon: {
        var h = Quickshell.env("HOME")
        if (stackDir.replace(/\/+$/, "") === h) return "user-home"
        var m = { Downloads: "folder-download", Documents: "folder-documents", Pictures: "folder-pictures", Music: "folder-music", Videos: "folder-videos", Desktop: "user-desktop" }
        return m[stackName] || "folder"
    }
    function openStackFolder() { Ui.run(["/usr/local/bin/smof-files", stackDir]) }
    function openStackItem(it) {
        var p = stackDir.replace(/\/+$/, "") + "/" + it.name
        stackPop.visible = false; Ui.menuOpen = false
        if (it.dir) Ui.run(["/usr/local/bin/smof-files", p]); else Ui.run(["/usr/local/bin/smof-fileops", "open", p])
    }
    function sizeText(b) { return b > 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : (b > 1048576 ? (b / 1048576).toFixed(1) + " MB" : (b > 1024 ? Math.round(b / 1024) + " KB" : b + " B")) }
    // ---- live feedback while something is dragged: tiles slide aside, the target lights up ----
    property int dragFrom: -1       // the tile being dragged inside the dock
    property int dragTo: -1         // where it would land
    property int extIns: -1         // a launcher from the desktop hovering over the dock: where it would be inserted
    // the picture that follows the pointer while a tile is dragged: its own window above everything, so it is never hidden
    property bool ghostOn: false
    property real ghostX: 0
    property real ghostY: 0
    property string ghostSrc: ""
    property int removeIdx: -1      // the tile being dragged out of the dock: the dock closes up around it
    readonly property real tailShift: removeIdx >= 0 ? -slotW / 2 : (extIns >= 0 ? slotW / 2 : 0)
    property string hoverTarget: "" // "trash", "stack" or "pill" while something hovers
    readonly property real slotW: ts + row.spacing
    function shiftFor(i) {
        if (removeIdx >= 0) return i === removeIdx ? 0 : (i < removeIdx ? slotW / 2 : -slotW / 2)
        if (extIns >= 0) return i >= extIns ? slotW / 2 : -slotW / 2
        if (dragFrom < 0 || i === dragFrom) return 0
        if (dragTo > dragFrom) return (i > dragFrom && i <= dragTo) ? -slotW : 0
        return (i >= dragTo && i < dragFrom) ? slotW : 0
    }
    // the desktop is dragging an icon over the dock: x and y are screen coordinates, kind is "app" or "file"
    // late hover messages must not light the dock up again after a drop, and a hover that stops coming ends by itself
    Timer { id: hoverLock; interval: 900 }
    Timer { id: hoverExpire; interval: 600; onTriggered: dock.hoverEnd() }
    function hoverAt(kind, gx, gy) {
        if (hoverLock.running) return
        hoverExpire.restart()
        var scrH = dock.screen ? dock.screen.height : Quickshell.screens[0].height
        var ly = gy - (scrH - dock.height)
        function hit(t) { var r = t.mapToItem(dock.contentItem, 0, 0); return gx >= r.x && gx <= r.x + t.width && ly >= r.y && ly <= r.y + t.height }
        extIns = -1
        if (hit(trashTile)) hoverTarget = "trash"
        else if (hit(stackTile)) hoverTarget = "stack"
        else if (kind === "app" && pill.x <= gx && gx <= pill.x + pill.width && ly >= pill.y - 10) {
            hoverTarget = "pill"
            var n = 0
            for (var i = 0; i < itemRep.count; i++) { var c = itemRep.itemAt(i); if (c && c.mapToItem(dock.contentItem, c.width / 2, 0).x < gx) n++ }
            extIns = n
        } else hoverTarget = ""
    }
    function hoverEnd() { hoverTarget = ""; extIns = -1; hoverExpire.stop() }
    // where a tile dropped at rowX lands among the others
    function dropIndex(from, rowX) {
        var n = 0
        for (var i = 0; i < itemRep.count; i++) {
            if (i === from) continue
            var c = itemRep.itemAt(i)
            if (c && c.x + c.width / 2 < rowX) n++
        }
        return n
    }
    // real app icons from the Papirus theme: our own apps by their window title, the rest by their desktop entry
    function iconFor(appId, title) {
        var t = title || ""
        if (t === "Settings") return "preferences-system"
        if (t === "Files") return "system-file-manager"
        if (t === "Upscaler") return "applications-graphics"
        if (t === "Smof Store") return "org.gnome.Software"
        var a = (appId || "")
        if (a.toLowerCase().indexOf("foot") >= 0) return "foot"
        var d = DesktopEntries.heuristicLookup(a)
        if (d && d.icon) return d.icon
        return a !== "" ? a.toLowerCase() : "application-x-executable"
    }
    // ---- things that go on without a window: store jobs and apps that were closed but still run ----
    property var jobs: []
    property var bg: []
    function pctOf(line) { var m = /(\d{1,3})%\s*$/.exec(line || ""); return m ? m[1] + "%" : "" }
    function jobName(j) { var n = j.n !== "" ? j.n.charAt(0).toUpperCase() + j.n.slice(1) : (j.src === "pacman" ? "the system" : "everything"); return (j.action === "install" ? "Installing " : (j.action === "uninstall" ? "Removing " : "Updating ")) + n }
    Process { id: jobsP; command: ["/usr/local/bin/smof-pkg", "jobs"]
        stdout: StdioCollector { onStreamFinished: { try { dock.jobs = JSON.parse(text).filter(function (j) { return j.status === "queued" || j.status === "running" }) } catch (e) {} } } }
    Process { id: lsP; command: ["sh", "-c", "ls $HOME/.local/state/smof-store/jobs/*.json 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: { if (text.trim() !== "") { if (!jobsP.running) jobsP.running = true } else if (dock.jobs.length > 0) dock.jobs = [] } } }
    Timer { interval: 2500; running: true; repeat: true; triggeredOnStart: true; onTriggered: { if (!lsP.running) lsP.running = true } }
    Process { id: bgP; command: ["/usr/local/bin/smof-bgapps", "list"]
        stdout: StdioCollector { onStreamFinished: { try { dock.bg = JSON.parse(text) } catch (e) {} } } }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { if (!bgP.running) bgP.running = true } }
    // the trash: a tile at the end, full or empty, files dropped on it go in
    property bool trashFull: false
    Process { id: trashP; command: ["sh", "-c", "ls -A \"$HOME/.local/share/Trash/files\" 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: dock.trashFull = text.trim() !== "" } }
    Timer { interval: 2500; running: true; repeat: true; triggeredOnStart: true; onTriggered: { if (!trashP.running) trashP.running = true } }
    function openTrash() { Ui.run(["sh", "-c", "exec /usr/local/bin/smof-files \"$HOME/.local/share/Trash/files\""]) }
    function trashMenu() {
        return [
            { header: dock.trashFull ? "Trash" : "Trash is empty" },
            { label: "Open Trash", run: function () { dock.openTrash() } },
            { label: "Empty Trash", danger: true, disabled: !dock.trashFull, run: function () { Ui.run(["/usr/local/bin/smof-files", "--empty-trash"]) } }
        ]
    }
    function dropToTrash(urls) {
        var ps = []
        for (var i = 0; i < urls.length; i++) { var u = String(urls[i]); if (u.indexOf("file://") === 0) ps.push(decodeURIComponent(u.substring(7))) }
        if (ps.length > 0) { Ui.run(["/usr/local/bin/smof-fileops", "trash"].concat(ps)); trashP.running = true }
    }
    function jobMenu(j) {
        return [
            { header: jobName(j) + (pctOf(j.line) !== "" ? "  " + pctOf(j.line) : "") },
            { label: "Show details", run: function () { Ui.run(["/usr/local/bin/smof-store", "log"]) } },
            { sep: true },
            { label: "Stop", danger: true, run: function () { Ui.run(["/usr/local/bin/smof-pkg", "kill", j.id]) } }
        ]
    }
    function bgMenu(b) {
        return [
            { header: (b.title || b.app || b.name) + "  in the background" },
            { label: "Quit", run: function () { Ui.run(["/usr/local/bin/smof-bgapps", "quit", String(b.pid)]); dock.bg = dock.bg.filter(function (x) { return x.pid !== b.pid }) } },
            { label: "Force quit", danger: true, run: function () { Ui.run(["/usr/local/bin/smof-bgapps", "kill", String(b.pid)]); dock.bg = dock.bg.filter(function (x) { return x.pid !== b.pid }) } }
        ]
    }

    // tile size: 60 normally, smaller when many windows would not fit on the screen
    readonly property int count: dock.items.length + dock.groups.length + (dock.jobs.length > 0 ? 1 : 0) + dock.bg.length + 2
    readonly property real ts: {
        var win = ToplevelManager.toplevels.values.length + dock.jobs.length + dock.bg.length > 0
        var avail = Math.max(300, dock.width - 64) - 28 - (win ? 2 : 0)
        var units = count + 0.2 * (count - 1) + (win ? 0.4 : 0)
        return Math.max(22, Math.min(Look.dockSize, Math.floor(avail / units)))
    }
    // when a window fills the screen the dock steps aside and comes back when the cursor touches the bottom edge
    readonly property var front: ToplevelManager.activeToplevel
    // where the focused window is, written by smof-front: a window that comes over this panel makes it step aside
    property var fr: ({ has: false, top: 0, bottom: 0, h: 0, fs: false })
    FileView {
        id: frontF
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/smof-front.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { dock.fr = JSON.parse(text()) } catch (e) {} }
    }
    readonly property bool covered: !!front && !front.minimized && fr.has && (fr.fs || (Ui.autohide && fr.h > 0 && fr.bottom > fr.h - 108))
    property bool reveal: false
    readonly property bool shown: !covered || reveal || Ui.menuOpen
    onCoveredChanged: { if (covered) { reveal = true; dhideT.restart() } else { reveal = false; dhideT.stop() } }
    Timer { id: dhideT; interval: 900; onTriggered: if (!Ui.menuOpen) dock.reveal = false }
    PanelWindow {
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 3
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-dock-edge"
        color: "transparent"
        visible: dock.covered && !dock.shown
        Timer { id: edgeT; interval: 450; onTriggered: { dock.reveal = true; dhideT.restart() } }
        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: edgeT.restart(); onExited: edgeT.stop() }
    }
    function launch(cmd) { Quickshell.execDetached({ command: cmd, workingDirectory: Quickshell.env("HOME") }) }

    // ---- context menu (right click) ----
    property var menuItems: []
    property Item menuAnchor: null
    property var pending: null
    // opening the same tile again closes its menu; anything else opens the new menu after the old one is gone
    function openMenu(item, entries) {
        if (ctx.visible && menuAnchor === item) { closeMenu(); return }
        Ui.closeOther("bar")
        ctx.visible = false
        pending = { item: item, entries: entries }
        openT.restart()
    }
    function closeMenu() { ctx.visible = false; openT.stop(); Ui.menuOpen = false }
    Timer { id: openT; interval: 40; onTriggered: { if (dock.pending) { dock.menuItems = dock.pending.entries; dock.menuAnchor = dock.pending.item; ctx.visible = true; Ui.menuOpen = true } } }
    Connections { target: Ui; function onDismiss() { dock.closeMenu(); stackPop.visible = false } }

    function windowMenu(tl) {
        return [
            { header: tl.title || "Window" },
            { label: tl.minimized ? "Show" : "Minimize", run: function () { if (tl.minimized) { tl.minimized = false; tl.activate() } else tl.minimized = true } },
            { label: tl.maximized ? "Restore size" : "Maximize", run: function () { tl.maximized = !tl.maximized } },
            { label: "Full screen", run: function () { tl.fullscreen = !tl.fullscreen } },
            { sep: true },
            dock.ownerKey(tl) !== "" ? { label: "Remove from dock", disabled: dock.ownerKey(tl) === "@launcher", run: function () { dock.unpin(dock.ownerKey(tl)) } }
                : { label: "Keep in dock", disabled: dock.keepKeyFor(tl) === "", run: function () { dock.pin(dock.keepKeyFor(tl)) } },
            { label: "Close", danger: true, run: function () { tl.close() } }
        ]
    }
    IpcHandler {
        target: "dock"
        function run(i: int): void { var it = dock.items[i]; if (it) dock.clickItem(it, dock.windowsOf(it.key)) }
        function launcher(i: int): void { var it = dock.items[i]; if (it) dock.openMenu(itemRep.itemAt(i), dock.itemMenu(it, dock.windowsOf(it.key))) }
        function pin(id: string): void { dock.pin(id) }
        function dropat(spec: string, x: int, y: int): void { dock.hoverEnd(); hoverLock.restart(); dock.dropAt(spec, x, y) }
        function hover(kind: string, x: int, y: int): void { dock.hoverAt(kind, x, y) }
        function hoverend(): void { dock.hoverEnd() }
        function unpin(id: string): void { dock.unpin(id) }
        function move(from: int, to: int): void { dock.moveItem(from, to) }
        function window(i: int): void { var g = dock.groups[i]; if (g) dock.openMenu(runRep.itemAt(i), dock.groupMenu(g, dock.windowsInGroup(g.key))) }
    }

    PopupWindow {
        id: ctx
        anchor.window: dock
        anchor.item: dock.menuAnchor
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        implicitWidth: 250
        implicitHeight: col.implicitHeight + 16
        color: "transparent"
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: 8
            radius: 22
            color: Theme.panelbg
            border.color: Theme.glassBorder
            Column {
                id: col
                x: 8; y: 8; width: parent.width - 16
                Repeater {
                    model: dock.menuItems
                    Item {
                        required property var modelData
                        width: col.width
                        height: modelData.sep ? 13 : 44
                        Rectangle { visible: !!modelData.sep; anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: Theme.i12 }
                        Rectangle {
                            visible: !modelData.sep && !modelData.header
                            anchors.fill: parent
                            radius: 14
                            color: Theme.acc
                            opacity: (!modelData.disabled && mm.containsMouse) ? .16 : 0
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }
                        T {
                            visible: !modelData.sep
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28; elide: Text.ElideRight
                            text: modelData.header || modelData.label || ""
                            font.pixelSize: modelData.header ? 14 : 17
                            w: modelData.header ? 560 : 460
                            color: modelData.header ? Theme.i55 : (modelData.disabled ? Theme.i5 : (modelData.danger ? (Theme.dark ? "#FFB59E" : "#B3401C") : Theme.ink))
                        }
                        MouseArea {
                            id: mm
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !modelData.sep && !modelData.header && !modelData.disabled
                            onClicked: { var f = modelData.run; dock.closeMenu(); if (f) f() }
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        id: stackPop
        anchor.window: dock
        anchor.item: stackTile
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        implicitWidth: 360
        implicitHeight: scol.implicitHeight + 24
        color: "transparent"
        visible: false
        onVisibleChanged: Ui.menuOpen = visible
        Rectangle {
            anchors.fill: parent; anchors.bottomMargin: 8; radius: 24
            color: Theme.panelbg; border.color: Theme.glassBorder
            Column {
                id: scol
                x: 12; y: 12; width: parent.width - 24; spacing: 2
                Item { width: parent.width; height: 46
                    T { x: 10; anchors.verticalCenter: parent.verticalCenter; text: dock.stackName; font.pixelSize: 19; w: 700 }
                    Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: ot.implicitWidth + 28; height: 34; radius: 17; color: Theme.moonbg
                        T { id: ot; anchors.centerIn: parent; text: "Open in Files"; font.pixelSize: 14; w: 560; color: Theme.acc }
                        MouseArea { anchors.fill: parent; onClicked: { stackPop.visible = false; dock.openStackFolder() } } } }
                Repeater {
                    model: dock.stackItems
                    Item {
                        required property var modelData
                        width: scol.width; height: 52
                        Rectangle { anchors.fill: parent; radius: 14; color: Theme.acc; opacity: sm.containsMouse ? .16 : 0 }
                        Image { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; sourceSize: Qt.size(102, 102); fillMode: Image.PreserveAspectFit
                            source: modelData.dir ? "file:///usr/share/smof/icons/folder" + Theme.sfx + ".svg" : "file:///usr/share/icons/Papirus/64x64/mimetypes/text-x-generic.svg" }
                        T { x: 56; y: 7; width: parent.width - 70; elide: Text.ElideMiddle; text: modelData.name; font.pixelSize: 16; w: 500 }
                        T { x: 56; y: 28; text: modelData.dir ? "Folder" : dock.sizeText(modelData.size); font.pixelSize: 13; color: Theme.i55 }
                        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; onClicked: dock.openStackItem(modelData) }
                    }
                }
                T { visible: dock.stackItems.length === 0; x: 10; height: 50; verticalAlignment: Text.AlignVCenter; text: "Nothing here yet"; font.pixelSize: 15; color: Theme.i55 }
            }
        }
    }

    PanelWindow {
        id: ghostWin
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-dock-ghost"
        color: "transparent"
        visible: dock.ghostOn
        mask: Region {}
        Image {
            x: dock.ghostX - width / 2; y: dock.ghostY - height / 2
            width: dock.ts * 1.1; height: width
            sourceSize: Qt.size(128, 128)
            source: dock.ghostSrc
            opacity: .96
        }
    }

    component Tile: Item {
        id: tile
        property string icon: ""
        property color bg: Theme.moonbg
        property bool active: false
        property bool dim: false
        signal clicked()
        signal rightClicked()
        width: dock.ts; height: dock.ts
        scale: ma.pressed ? .94 : (ma.containsMouse ? 1.16 : 1)
        opacity: (dragging && !settling) ? 0 : (dim ? .55 : 1)
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: tile.out ? 90 : 200 } }
        property bool running: false
        property string iconUrl: ""
        // the icon sits on nothing, like on a Mac: the shape of the picture is what tells apps apart
        Image {
            id: glyph
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top
            width: tile.width * 0.92; height: width
            sourceSize: Qt.size(128, 128)
            source: tile.iconUrl !== "" ? tile.iconUrl : "file:///usr/share/icons/Papirus/64x64/apps/" + tile.icon + ".svg"
            onStatusChanged: if (status === Image.Error && source.toString().indexOf("application-default-icon") < 0) source = "file:///usr/share/icons/Papirus/64x64/apps/application-default-icon.svg"
        }
        Rectangle { visible: tile.running || tile.active; anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.bottom; anchors.topMargin: 3
            width: tile.active ? 14 : 5; height: 5; radius: 2.5; color: Theme.dark ? "#F4F0FF" : "#1B1230"; opacity: tile.active ? 1 : .75
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
        // drag to reorder: the tile follows the pointer, and where it is let go decides its new place
        property bool reorderable: false
        property bool dragging: false
        property bool settling: false
        property real dragDx: 0
        property real dragDy: 0
        property real shift: 0                 // other tiles slide aside while one is dragged
        property bool out: false
        signal dropped(real rowX)
        signal droppedOut(real gx, real gy)
        signal dragMoved(real rowX, bool out)
        Behavior on shift { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Behavior on dragDx { enabled: tile.settling; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on dragDy { enabled: tile.settling; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        transform: Translate { x: tile.dragDx + tile.shift; y: tile.dragDy }
        z: (dragging || settling) ? 5 : 0
        property var settleDone: null
        // slide into the place it was dropped on, then let the dock rearrange for real
        function settle(dx, done) { settleDone = done; settling = true; dragDx = dx; dragDy = 0; settleT.restart() }
        Timer { id: settleT; interval: 170; onTriggered: { var f = tile.settleDone; tile.settleDone = null; tile.settling = false; tile.dragging = false; tile.dragDx = 0; tile.dragDy = 0; if (f) f() } }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
            property real sx: 0
            property real sy: 0
            property bool moved: false
            onPressed: (m) => { var p = tile.mapToItem(row, m.x, m.y); sx = p.x; sy = p.y; moved = false }
            onPositionChanged: (m) => {
                if (!pressed || !tile.reorderable || tile.settling) return
                var p = tile.mapToItem(row, m.x, m.y)
                if (!tile.dragging && Math.abs(p.x - sx) + Math.abs(p.y - sy) > 10) { tile.dragging = true; moved = true; dock.closeMenu() }
                if (tile.dragging) {
                    tile.dragDx = p.x - sx; tile.dragDy = p.y - sy
                    var q = tile.mapToItem(dock.contentItem, m.x, m.y)
                    // far above the dock: it is going to the desktop
                    tile.out = q.y < pill.y - 30
                    dock.ghostSrc = glyph.source.toString()
                    dock.ghostX = q.x
                    dock.ghostY = (dock.screen ? dock.screen.height : Quickshell.screens[0].height) - dock.height + q.y
                    dock.ghostOn = true
                    tile.dragMoved(p.x, tile.out)
                }
            }
            onReleased: (m) => {
                if (!tile.dragging || tile.settling) return
                dock.ghostOn = false
                var p = tile.mapToItem(row, m.x, m.y)
                var q = tile.mapToItem(dock.contentItem, m.x, m.y)
                var out = tile.out
                if (out) {
                    tile.out = false; tile.dragging = false; tile.dragDx = 0; tile.dragDy = 0
                    tile.droppedOut(q.x, (dock.screen ? dock.screen.height : Quickshell.screens[0].height) - dock.height + q.y)
                } else tile.dropped(p.x)
            }
            onCanceled: { if (tile.dragging && !tile.settling) { tile.dragging = false; tile.out = false; tile.dragDx = 0; tile.dragDy = 0; dock.ghostOn = false; dock.dragFrom = -1; dock.dragTo = -1; dock.removeIdx = -1; dock.hoverTarget = "" } }
            onClicked: (m) => { if (moved) return; if (m.button === Qt.RightButton) tile.rightClicked(); else tile.clicked() } }
    }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dock.shown ? 24 : -120
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        HoverHandler { onHoveredChanged: { if (dock.covered) { if (hovered) { dock.reveal = true; dhideT.stop() } else dhideT.restart() } } }
        width: row.implicitWidth + 28 + (dock.extIns >= 0 ? dock.slotW : 0) - (dock.removeIdx >= 0 ? dock.slotW : 0)
        height: dock.ts + 28
        radius: height * 0.4
        opacity: Ui.entered ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: 600 } NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } }
        color: Theme.glass
        border.color: dock.hoverTarget === "pill" ? Theme.acc : Theme.glassBorder
        border.width: dock.hoverTarget === "pill" ? 2 : 1
        Behavior on color { ColorAnimation { duration: 400 } }
        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: dock.ts * 0.2
            Repeater {
                id: itemRep
                model: dock.items
                Tile {
                    id: itTile
                    required property var modelData
                    required property int index
                    readonly property var wins: dock.windowsOf(modelData.key)
                    icon: modelData.icon.charAt(0) === "/" ? "" : modelData.icon
                    iconUrl: modelData.icon.charAt(0) === "/" ? "file://" + modelData.icon : ""
                    running: wins.length > 0
                    active: dock.anyActive(wins)
                    reorderable: modelData.key !== "@launcher"
                    onClicked: dock.clickItem(modelData, wins)
                    onRightClicked: dock.openMenu(this, dock.itemMenu(modelData, wins))
                    shift: dock.shiftFor(index)
                    onDragMoved: (rowX, out) => {
                        dock.dragFrom = index
                        var overTrash = rowX >= trashTile.x && rowX <= trashTile.x + trashTile.width
                        dock.removeIdx = (out || overTrash) ? index : -1      // leaving the dock: it closes up around the gap
                        if (rowX >= stackTile.x && rowX <= stackTile.x + stackTile.width) dock.dragTo = index
                        else dock.dragTo = dock.dropIndex(index, rowX)
                        dock.hoverTarget = (!out && overTrash) ? "trash" : ""
                    }
                    onDropped: (rowX) => {
                        var me = itTile
                        dock.hoverTarget = ""
                        dock.removeIdx = -1
                        if (rowX >= trashTile.x && rowX <= trashTile.x + trashTile.width) {
                            dock.dragFrom = -1; dock.dragTo = -1; me.dragging = false; me.dragDx = 0; me.dragDy = 0; dock.unpin(modelData.key)
                        } else if (rowX >= stackTile.x && rowX <= stackTile.x + stackTile.width) {
                            me.settle(0, function () { dock.dragFrom = -1; dock.dragTo = -1; dock.removeIdx = -1 })
                        } else {
                            var t = dock.dropIndex(index, rowX)
                            me.settle((t - index) * dock.slotW, function () { dock.dragFrom = -1; dock.dragTo = -1; dock.moveItem(index, t) })
                        }
                    }
                    onDroppedOut: (gx, gy) => { dock.dragFrom = -1; dock.dragTo = -1; dock.removeIdx = -1; dock.hoverTarget = ""; dock.toDesktop(modelData, gx, gy); dock.unpin(modelData.key) }
                }
            }
            // apps that run but are not kept in the dock join the same row
            Repeater {
                id: runRep
                model: dock.groups
                Tile {
                    required property var modelData
                    shift: dock.tailShift
                    readonly property var wins: dock.windowsInGroup(modelData.key)
                    icon: modelData.icon
                    running: true
                    active: dock.anyActive(wins)
                    dim: wins.length > 0 && wins.every(function (t) { return t.minimized })
                    onClicked: dock.cycle(wins)
                    onRightClicked: dock.openMenu(this, dock.groupMenu(modelData, wins))
                }
            }
            Rectangle {
                transform: Translate { x: dock.tailShift }
                visible: dock.jobs.length > 0 || dock.bg.length > 0
                width: 2; height: dock.ts * 0.67; radius: 1; color: Theme.i12
                anchors.verticalCenter: parent.verticalCenter
            }
            // a store job keeps showing after the store is closed
            Tile {
                id: jobTile
                shift: dock.tailShift
                visible: dock.jobs.length > 0
                width: visible ? dock.ts : 0
                icon: "org.gnome.Software"
                bg: Theme.moonbg
                readonly property var j: dock.jobs.length ? dock.jobs[0] : null
                onClicked: Ui.run(["/usr/local/bin/smof-store", "log"])
                onRightClicked: if (j) dock.openMenu(this, dock.jobMenu(j))
                Item {
                    anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: 2; anchors.bottomMargin: 2
                    width: dock.ts * 0.34; height: width
                    Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.acc }
                    Canvas {
                        anchors.fill: parent
                        onPaint: { var c = getContext("2d"); c.reset(); c.lineWidth = 2; c.strokeStyle = "#ffffff"; c.lineCap = "round"; var r = width / 2 - 3.5; c.beginPath(); c.arc(width / 2, height / 2, r, 0, 4.4); c.stroke() }
                        onWidthChanged: requestPaint()
                        RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: jobTile.visible }
                    }
                }
            }
            // closed apps that still run in the background, dimmed, right click to end them
            Repeater {
                model: dock.bg
                Tile {
                    required property var modelData
                    shift: dock.tailShift
                    icon: dock.iconFor(modelData.app, modelData.title)
                    bg: Theme.moonbg
                    dim: true
                    onClicked: dock.openMenu(this, dock.bgMenu(modelData))
                    onRightClicked: dock.openMenu(this, dock.bgMenu(modelData))
                }
            }
            Rectangle { width: 2; height: dock.ts * 0.67; radius: 1; color: Theme.i12; anchors.verticalCenter: parent.verticalCenter
                transform: Translate { x: dock.tailShift } }
            Tile {
                id: stackTile
                shift: dock.tailShift
                icon: dock.stackIcon
                iconUrl: "file:///usr/share/icons/Papirus/64x64/places/" + dock.stackIcon + ".svg"
                onClicked: { if (stackPop.visible) { stackPop.visible = false } else { dock.closeMenu(); stackP.running = true; stackPop.visible = true } }
                Rectangle { anchors.fill: parent; radius: width / 3; color: Theme.acc; opacity: (stackDrop.containsDrag || dock.hoverTarget === "stack") ? .3 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
                DropArea { id: stackDrop; anchors.fill: parent
                    onDropped: (d) => {
                        var ps = []
                        for (var i = 0; i < d.urls.length; i++) { var u = String(d.urls[i]); if (u.indexOf("file://") === 0) ps.push(decodeURIComponent(u.substring(7))) }
                        if (ps.length > 0) { Ui.run(["/usr/local/bin/smof-fileops", "move", dock.stackDir].concat(ps)); stackRefT.restart() }
                    } }
                onRightClicked: dock.openMenu(this, [ { header: dock.stackName }, { label: "Open in Files", run: function () { dock.openStackFolder() } }, { label: "Choose folder in Settings", run: function () { Ui.run(["/usr/local/bin/smof-settings", "desktop"]) } } ])
            }
            Tile {
                id: trashTile
                shift: dock.tailShift
                icon: "user-trash"
                iconUrl: "file:///usr/share/icons/Papirus/64x64/places/" + (dock.trashFull ? "user-trash-full" : "user-trash") + ".svg"
                onClicked: dock.openTrash()
                onRightClicked: dock.openMenu(this, dock.trashMenu())
                Rectangle { anchors.fill: parent; radius: width / 3; color: Theme.acc; opacity: (trashDrop.containsDrag || dock.hoverTarget === "trash") ? .3 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
                DropArea { id: trashDrop; anchors.fill: parent; onDropped: (d) => dock.dropToTrash(d.urls) }
            }
        }
    }
}
