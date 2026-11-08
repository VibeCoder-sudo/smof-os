import Quickshell
import Quickshell.Io
import QtQuick

// the file manager: places on the left, a toolbar, the folder as a grid or a list, a context menu
FloatingWindow {
    id: win
    title: "Files"
    readonly property real scrW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1366
    readonly property real scrH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 768
    // never larger than the screen minus the bar and the dock
    implicitWidth: Math.min(1000, scrW - 24)
    implicitHeight: Math.min(660, scrH - 210)
    minimumSize: Qt.size(Math.min(620, implicitWidth), Math.min(420, implicitHeight))
    readonly property bool compact: width < 600
    color: Theme.winbg
    visible: true
    onVisibleChanged: if (!visible) Qt.quit()

    readonly property string home: Quickshell.env("HOME")
    property string cwd: ""
    property var items: []
    property string err: ""
    property bool hidden: false
    property bool grid: true
    property string sel: ""            // the entry clicked last
    property var selSet: ({})          // names of all selected entries
    property string anchorName: ""
    property string sortBy: "name"     // name, size, date
    property bool sortDesc: false
    property string dragUris: ""
    property int dragCount: 0
    property var propsInfo: null
    property string viewing: ""         // name of the picture shown in the viewer
    property string filter: ""
    property var back: []
    property var fwd: []
    property var clip: ({ mode: "", paths: [] })
    property string note: ""
    property var places: []
    property var drives: []
    property string busyDev: ""
    property string renaming: ""
    property bool admin: false          // folder shown and changed with administrator rights (sudo, the permission popup asks)
    property bool asking: false

    readonly property bool inTrash: cwd.indexOf("/.local/share/Trash/files") >= 0
    readonly property var shown: {
        var q = filter.trim().toLowerCase()
        var arr = items.filter(function (i) { return q === "" || i.name.toLowerCase().indexOf(q) >= 0 })
        var k = sortBy, d = sortDesc ? -1 : 1
        arr = arr.slice().sort(function (a, b) {
            if (a.dir !== b.dir) return a.dir ? -1 : 1
            var r = 0
            if (k === "size") r = a.size - b.size
            else if (k === "date") r = a.mtime - b.mtime
            if (r === 0) r = a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0)
            return r * d
        })
        return arr
    }
    function pathOf(name) { return (cwd === "/" ? "" : cwd) + "/" + name }
    function selItem() { for (var i = 0; i < items.length; i++) if (items[i].name === sel) return items[i]; return null }
    function isSel(n) { return !!selSet[n] }
    function setSel(names, primary) { var o = {}; for (var i = 0; i < names.length; i++) o[names[i]] = true; selSet = o; sel = primary !== undefined ? primary : (names.length ? names[names.length - 1] : "") }
    function selNames() { var out = []; for (var i = 0; i < items.length; i++) if (selSet[items[i].name]) out.push(items[i].name); return out }
    function selPaths() { return selNames().map(function (n) { return pathOf(n) }) }
    function clickItem(name, mods) {
        if (mods & Qt.ControlModifier) {
            var o = Object.assign({}, selSet)
            if (o[name]) delete o[name]; else o[name] = true
            selSet = o; sel = name; anchorName = name
        } else if ((mods & Qt.ShiftModifier) && anchorName !== "") {
            var a = -1, b = -1
            for (var i = 0; i < shown.length; i++) { if (shown[i].name === anchorName) a = i; if (shown[i].name === name) b = i }
            if (a >= 0 && b >= 0) { var names = []; for (var j = Math.min(a, b); j <= Math.max(a, b); j++) names.push(shown[j].name); setSel(names, name); return }
            setSel([name], name); anchorName = name
        } else { setSel([name], name); anchorName = name }
    }
    function selectAll() { setSel(shown.map(function (i) { return i.name })) }
    function dirOf(p) { var i = p.lastIndexOf("/"); return i <= 0 ? "/" : p.slice(0, i) }
    function localPaths(urls) { var out = []; for (var i = 0; i < urls.length; i++) { var u = urls[i].toString(); if (u.indexOf("file://") === 0) out.push(decodeURIComponent(u.slice(7))) } return out }
    function beginDrag(name) {
        if (!isSel(name)) { setSel([name], name); anchorName = name }
        var ps = selPaths()
        dragCount = ps.length
        dragUris = ps.map(function (p) { return "file://" + encodeURI(p) }).join("\r\n") + "\r\n"
    }
    // something was dropped on a folder (dest): move it there, copy when the copy key was held
    function dropOn(dest, drop) {
        if (!drop.hasUrls) return
        var paths = localPaths(drop.urls).filter(function (p) { return dirOf(p) !== dest && p !== dest && dest.indexOf(p + "/") !== 0 })
        if (paths.length === 0) return
        var mode = drop.proposedAction === Qt.CopyAction ? "copy" : "move"
        drop.acceptProposedAction()
        op([mode, dest].concat(paths))
    }

    function crumbs() {
        var out = [{ name: "/", path: "/" }]
        var parts = cwd.split("/").filter(function (x) { return x !== "" })
        var p = ""
        for (var i = 0; i < parts.length; i++) { p += "/" + parts[i]; out.push({ name: parts[i], path: p }) }
        return out
    }
    function fmtSize(n) {
        if (n < 1024) return n + " B"
        if (n < 1048576) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB"
        if (n < 1073741824) return (n / 1048576).toFixed(n < 10485760 ? 1 : 0) + " MB"
        return (n / 1073741824).toFixed(1) + " GB"
    }
    function fmtDate(ms) {
        var d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return "Today " + Qt.formatDateTime(d, "HH:mm")
        return Qt.formatDateTime(d, d.getFullYear() === now.getFullYear() ? "d MMM HH:mm" : "d MMM yyyy")
    }
    function isImage(n) { return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(n) }
    function extOf(n) { var i = n.lastIndexOf("."); return i > 0 && i < n.length - 1 ? n.slice(i + 1, i + 5).toUpperCase() : "" }

    // ---- navigation ----
    function go(path, remember) {
        if (path === cwd) { refresh(); return }
        if (remember !== false && cwd !== "") { back = back.concat([cwd]); fwd = [] }
        cwd = path; setSel([]); filter = ""; renaming = ""
        refresh()
    }
    function goBack() { if (back.length === 0) return; var p = back[back.length - 1]; back = back.slice(0, -1); fwd = fwd.concat([cwd]); cwd = p; setSel([]); refresh() }
    function goFwd() { if (fwd.length === 0) return; var p = fwd[fwd.length - 1]; fwd = fwd.slice(0, -1); back = back.concat([cwd]); cwd = p; setSel([]); refresh() }
    function goUp() { if (cwd === "/") return; var i = cwd.lastIndexOf("/"); go(i <= 0 ? "/" : cwd.slice(0, i)) }
    function refresh() { if (!lsP.running) lsP.running = true; else lsAgain = true }
    property bool lsAgain: false
    function openItem(it) {
        if (!it) return
        if (it.dir) { go(pathOf(it.name)); return }
        if (isImage(it.name)) { viewing = it.name; return }
        openP.command = ["/usr/local/bin/smof-fileops", "open", pathOf(it.name)]
        openP.running = true
    }
    function op(args, then) { opP.then = then || null; opP.command = (admin ? ["sudo"] : []).concat(["/usr/local/bin/smof-fileops"]).concat(args); opP.running = true }
    function goAdmin() { admin = true; asking = true; items = []; err = ""; refresh() }
    function leaveAdmin() { admin = false; refresh() }

    Process {
        id: lsP
        command: (win.admin ? ["sudo"] : []).concat(["/usr/local/bin/smof-fileops", "ls", win.cwd, win.hidden ? "hidden" : ""])
        stdout: StdioCollector {
            onStreamFinished: {
                var ok = true
                try { var o = JSON.parse(text); win.items = o.items || []; win.err = o.error || "" } catch (e) { ok = false }
                win.asking = false
                if (!ok && win.admin) { win.admin = false; win.note = "Administrator access was not given"; win.items = []; win.err = "No permission to open this folder" }
                if (win.sel !== "" && !win.selItem()) win.setSel([])
                if (win.lsAgain) { win.lsAgain = false; lsP.running = true }
            }
        }
    }
    Process {
        id: opP
        property var then: null
        stdout: StdioCollector {
            onStreamFinished: {
                var r = {}
                try { r = JSON.parse(text) } catch (e) {}
                if (r.ok === false) win.note = r.error || "That did not work"
                if (opP.then) opP.then(r)
                win.refresh()
            }
        }
    }
    Process {
        id: openP
        stdout: StdioCollector { onStreamFinished: { try { var r = JSON.parse(text); if (r.ok === false) win.note = r.error } catch (e) {} } }
    }
    Process {
        id: plP
        command: ["/usr/local/bin/smof-fileops", "places"]
        stdout: StdioCollector { onStreamFinished: { try { win.places = JSON.parse(text) } catch (e) {} } }
    }
    Process {
        id: drvP
        command: ["/usr/local/bin/smof-fileops", "drives"]
        stdout: StdioCollector { onStreamFinished: { try { win.drives = JSON.parse(text) } catch (e) {} } }
    }
    Process {
        id: mntP
        property string dev: ""
        stdout: StdioCollector {
            onStreamFinished: {
                win.busyDev = ""
                var r = {}
                try { r = JSON.parse(text) } catch (e) {}
                if (r.ok && r.path) win.go(r.path)
                else win.note = r.error || "Administrator access was not given"
                drvP.running = true
            }
        }
    }
    Process {
        id: umP
        property string mount: ""
        stdout: StdioCollector {
            onStreamFinished: {
                win.busyDev = ""
                var r = {}
                try { r = JSON.parse(text) } catch (e) {}
                if (r.ok) { win.note = "Safe to remove"; if (win.cwd.indexOf(umP.mount) === 0) win.go(win.home) }
                else win.note = r.error || "Could not unmount"
                drvP.running = true
            }
        }
    }
    function openDrive(d) {
        if (d.mount !== "") { go(d.mount); return }
        if (busyDev !== "") return
        busyDev = d.dev
        mntP.command = ["sudo", "/usr/local/bin/smof-fileops", "mountdev", d.dev, Quickshell.env("USER")]
        mntP.running = true
    }
    function ejectDrive(d) {
        if (busyDev !== "") return
        busyDev = d.dev; umP.mount = d.mount
        umP.command = ["sudo", "/usr/local/bin/smof-fileops", "umountdev", d.dev]
        umP.running = true
    }
    Timer { interval: 4000; repeat: true; running: win.visible && win.busyDev === ""; onTriggered: drvP.running = true }
    Timer { interval: 3000; repeat: true; running: win.visible; onTriggered: if (win.renaming === "") win.refresh() }
    Timer { id: noteT; interval: 4000; running: win.note !== ""; onTriggered: win.note = "" }
    Component.onCompleted: {
        var p = Quickshell.env("SMOF_PATH")
        cwd = (p && p !== "") ? p : home
        plP.running = true
        drvP.running = true
        refresh()
    }

    // ---- picture viewer ----
    function pictures() { return shown.filter(function (i) { return !i.dir && isImage(i.name) }) }
    function stepPicture(d) {
        var ps = pictures(); if (ps.length === 0) return
        var k = 0
        for (var i = 0; i < ps.length; i++) if (ps[i].name === viewing) k = i
        k = (k + d + ps.length) % ps.length
        viewing = ps[k].name
        setSel([viewing], viewing)
    }

    // ---- actions ----
    function newFolder() { op(["mkdir", cwd, "New Folder"], function (r) { if (r.path) { var n = r.path.split("/").pop(); win.setSel([n], n); win.renaming = n } }) }
    function newFile() { op(["touch", cwd, "New file.txt"], function (r) { if (r.path) { var n = r.path.split("/").pop(); win.setSel([n], n); win.renaming = n } }) }
    function trashSel() { var ps = selPaths(); if (ps.length === 0) return; setSel([]); op(["trash"].concat(ps), function () { Ui.sound("trash") }) }
    // trash: restore, delete for good, empty. Deleting for good always asks first.
    property var purgeAsk: null            // { paths: [...] } or { all: true, count: n }
    function restoreSel() { var ps = selPaths(); if (ps.length === 0) return; setSel([]); op(["restore"].concat(ps), function (r) { win.note = r.count === 1 ? "Put back" : r.count + " items put back" }) }
    function askPurgeSel() { var ps = selPaths(); if (ps.length) purgeAsk = { paths: ps, count: ps.length } }
    function askEmpty() { purgeAsk = { all: true, count: items.length } }
    function doPurge() {
        var a = purgeAsk; purgeAsk = null; if (!a) return
        setSel([])
        op(a.all ? ["emptytrash"] : ["purge"].concat(a.paths), function (r) { win.note = "Deleted for good"; Ui.sound("trash") })
    }
    readonly property int banner: inTrash && items.length > 0 && !admin ? 52 : 0
    function copySel(cut) { var ps = selPaths(); if (ps.length === 0) return; clip = { mode: cut ? "move" : "copy", paths: ps }; note = (cut ? "Cut " : "Copied ") + (ps.length === 1 ? sel : ps.length + " items") }
    function pasteInto(dir) { if (clip.paths.length === 0) return; var m = clip.mode; op([m, dir].concat(clip.paths)); if (m === "move") clip = { mode: "", paths: [] } }
    function pasteHere() { pasteInto(cwd) }
    function duplicateSel() { var ps = selPaths(); if (ps.length) op(["copy", cwd].concat(ps)) }
    function zipSel() { var ps = selPaths(); if (ps.length) op(["zip", cwd].concat(ps), function (r) { if (r.path) { var n = r.path.split("/").pop(); win.setSel([n], n) } }) }
    function doRename(name) {
        var old = renaming; renaming = ""
        if (name === "" || name === old) return
        op(["rename", pathOf(old), name], function (r) { if (r.path) win.setSel([name], name) })
    }
    function copyPath(p) { Quickshell.execDetached(["sh", "-c", "printf %s \"$0\" | wl-copy", p]); note = "Path copied" }
    function inTerminal(dir) { Quickshell.execDetached({ command: ["foot", "-D", dir], workingDirectory: dir }) }
    // ---- picture upscaling (smof-upscale, a small Real-ESRGAN network running on the CPU) ----
    property bool upBusy: false
    Process {
        id: upP
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var o = JSON.parse(line)
                    if (o.progress !== undefined) win.note = "Upscaling... " + o.progress + "%"
                    else if (o.ok) { var n = o.path.split("/").pop(); win.note = "Saved " + n + "  " + o.width + " x " + o.height; if (o.path.indexOf(win.cwd + "/") === 0) win.setSel([n], n); win.refresh() }
                    else if (o.ok === false) win.note = o.error || "Upscaling did not work"
                } catch (e) {}
            }
        }
        onExited: win.upBusy = false
    }
    function upscale(path, scale, mode) {
        if (upBusy) { note = "Another picture is still being upscaled"; return }
        upBusy = true; note = "Upscaling..."
        upP.command = ["/usr/local/bin/smof-upscale", path, "--scale", String(scale), "--mode", mode]
        upP.running = true
    }
    function showProps(p) { propsP.command = ["/usr/local/bin/smof-fileops", "props", p]; propsP.running = true }
    Process {
        id: propsP
        stdout: StdioCollector { onStreamFinished: { try { win.propsInfo = JSON.parse(text) } catch (e) { win.note = "Could not read the details" } } }
    }
    // picture as wallpaper: copied where the lock screen can read it too
    Process {
        id: wpP
        property string target: ""
        property string path: ""
        onExited: (code) => {
            if (code !== 0) return
            if (target === "desktop") { Look.wpImage = path; Look.wpMode = "image" } else { Look.lockImage = path; Look.lockMode = "image" }
            win.note = target === "desktop" ? "Set as desktop wallpaper" : "Set as lock screen wallpaper"
        }
    }
    function setWallpaper(src, target) {
        var ext = src.split(".").pop().toLowerCase()
        var dest = "/var/lib/smof/wp/" + target + "-" + Date.now() + "." + ext
        wpP.target = target; wpP.path = dest
        wpP.command = ["sh", "-c", "mkdir -p /var/lib/smof/wp && cp -f \"$0\" \"$1\" && chmod 644 \"$1\"", src, dest]
        wpP.running = true
    }

    // ---- the context menu: a window of its own, so it can reach outside the Files window ----
    property var ctxItems: []
    property real ctxX: 0
    property real ctxY: 0
    function openCtx(x, y, target) {
        ctxItems = buildMenu(target)
        ctxX = x; ctxY = y
        ctx.visible = false
        ctxT.restart()
    }
    function closeCtx() { ctx.visible = false }
    Timer { id: ctxT; interval: 30; onTriggered: ctx.visible = true }
    function buildMenu(it) {
        var m = []
        var names = selNames()
        var multi = names.length > 1
        var hasPaste = clip.paths.length > 0
        if (it) {
            if (!multi) m.push({ label: it.dir ? "Open" : "Open", run: function () { openItem(it) } })
            if (!multi && it.dir) {
                m.push({ label: "Open in Terminal", run: function () { inTerminal(pathOf(it.name)) } })
                if (!admin) m.push({ label: "Open as administrator", run: function () { go(pathOf(it.name)); goAdmin() } })
            }
            if (!multi && !it.dir && isImage(it.name)) {
                m.push({ sep: true })
                m.push({ label: "Open in Upscaler", run: function () { Quickshell.execDetached(["/usr/local/bin/smof-upscaler"].concat(names.map(function (n) { return pathOf(n) }))) } })
                m.push({ header: "Upscale picture" })
                m.push({ label: "2x, smart", off: upBusy, run: function () { upscale(pathOf(it.name), 2, "smart") } })
                m.push({ label: "4x, smart", off: upBusy, run: function () { upscale(pathOf(it.name), 4, "smart") } })
                m.push({ label: "4x, best (slow)", off: upBusy, run: function () { upscale(pathOf(it.name), 4, "best") } })
                m.push({ label: "2x, quick", off: upBusy, run: function () { upscale(pathOf(it.name), 2, "fast") } })
                m.push({ sep: true })
                m.push({ label: "Set as desktop wallpaper", run: function () { setWallpaper(pathOf(it.name), "desktop") } })
                m.push({ label: "Set as lock screen wallpaper", run: function () { setWallpaper(pathOf(it.name), "lock") } })
            }
            m.push({ sep: true })
            m.push({ label: "Cut", hint: "Ctrl+X", run: function () { copySel(true) } })
            m.push({ label: "Copy", hint: "Ctrl+C", run: function () { copySel(false) } })
            if (!multi && it.dir) m.push({ label: "Paste into folder", off: !hasPaste, run: function () { pasteInto(pathOf(it.name)) } })
            if (!multi && it.dir) m.push({ label: "Use as dock folder", run: function () { Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config\" && printf '{\"dir\": \"%s\"}' \"$0\" > \"$HOME/.config/smof-dock-stack.json\"", pathOf(it.name)]) } })
            m.push({ label: "Duplicate", run: function () { duplicateSel() } })
            m.push({ label: "Compress to ZIP", run: function () { zipSel() } })
            m.push({ sep: true })
            if (!multi) m.push({ label: "Rename", hint: "F2", run: function () { renaming = it.name } })
            m.push({ label: "Copy path", run: function () { copyPath(pathOf(it.name)) } })
            m.push({ label: "Properties", run: function () { showProps(pathOf(it.name)) } })
            m.push({ sep: true })
            if (inTrash) {
                m.push({ label: "Put back", run: function () { restoreSel() } })
                m.push({ label: multi ? "Delete " + names.length + " items for good" : "Delete for good", danger: true, run: function () { askPurgeSel() } })
            } else m.push({ label: multi ? "Move " + names.length + " items to Trash" : "Move to Trash", hint: "Del", danger: true, run: function () { trashSel() } })
        } else {
            if (!inTrash) {
                m.push({ label: "New folder", hint: "Ctrl+Shift+N", run: function () { newFolder() } })
                m.push({ label: "New text file", run: function () { newFile() } })
                m.push({ sep: true })
            }
            if (inTrash) { m.push({ label: "Empty Trash", danger: true, off: items.length === 0, run: function () { askEmpty() } }); m.push({ sep: true }) }
            m.push({ label: "Paste", hint: "Ctrl+V", off: !hasPaste || inTrash, run: function () { pasteHere() } })
            m.push({ label: "Select all", hint: "Ctrl+A", run: function () { selectAll() } })
            m.push({ sep: true })
            m.push({ header: "Sort by" })
            m.push({ label: "Name", check: sortBy === "name", run: function () { sortBy = "name" } })
            m.push({ label: "Size", check: sortBy === "size", run: function () { sortBy = "size" } })
            m.push({ label: "Date modified", check: sortBy === "date", run: function () { sortBy = "date" } })
            m.push({ label: "Reverse order", check: sortDesc, run: function () { sortDesc = !sortDesc } })
            m.push({ sep: true })
            m.push({ label: grid ? "View as list" : "View as grid", run: function () { grid = !grid } })
            m.push({ label: hidden ? "Hide hidden files" : "Show hidden files", hint: "Ctrl+H", run: function () { hidden = !hidden; refresh() } })
            m.push({ sep: true })
            m.push({ label: "Open in Terminal", run: function () { inTerminal(cwd) } })
            if (!admin) m.push({ label: "Open as administrator", run: function () { goAdmin() } })
            m.push({ label: "Properties", run: function () { showProps(cwd) } })
        }
        return m
    }
    PopupWindow {
        id: ctx
        anchor.window: win
        anchor.rect: Qt.rect(win.ctxX, win.ctxY, 1, 1)
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        implicitWidth: 310
        implicitHeight: ccol.implicitHeight + 16
        color: "transparent"
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Theme.menubg
            border.color: Theme.glassBorder
            Column {
                id: ccol
                x: 8; y: 8; width: parent.width - 16
                Repeater {
                    model: win.ctxItems
                    Item {
                        required property var modelData
                        width: ccol.width
                        height: modelData.sep ? 13 : (modelData.header ? 30 : 38)
                        Rectangle { visible: !!modelData.sep; anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: Theme.i12 }
                        T { visible: !!modelData.header; x: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.header || ""; font.pixelSize: 13; w: 600; color: Theme.i55 }
                        Rectangle { visible: !modelData.sep && !modelData.header; anchors.fill: parent; radius: 13; color: Theme.acc; opacity: !modelData.off && cma2.containsMouse ? .16 : 0; Behavior on opacity { NumberAnimation { duration: 90 } } }
                        T {
                            visible: !modelData.sep && !modelData.header
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28 - (modelData.hint ? 96 : 0); elide: Text.ElideRight
                            text: (modelData.check ? "\u2713  " : (modelData.check === false ? "    " : "")) + (modelData.label || "")
                            font.pixelSize: 16; w: 460
                            color: modelData.off ? Theme.i5 : (modelData.danger ? Theme.errfg : Theme.ink)
                        }
                        T { visible: !!modelData.hint; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.hint || ""; font.pixelSize: 13; color: Theme.i5 }
                        MouseArea { id: cma2; anchors.fill: parent; hoverEnabled: true; enabled: !modelData.sep && !modelData.header && !modelData.off
                            onClicked: { var f = modelData.run; win.closeCtx(); if (f) f() } }
                    }
                }
            }
        }
    }

    // ---- small building blocks ----
    component TBtn: Item {
        id: tb
        property string glyph: ""
        property string icon: ""          // list, grid, eye or eyeoff: drawn, not typed
        property bool enabled2: true
        signal clicked()
        width: 38; height: 38
        opacity: enabled2 ? 1 : .35
        Rectangle { anchors.fill: parent; radius: 19; color: Theme.ink; opacity: tma.pressed ? .16 : (tma.containsMouse && tb.enabled2 ? .09 : 0); Behavior on opacity { NumberAnimation { duration: 100 } } }
        T { visible: tb.icon === ""; anchors.centerIn: parent; text: tb.glyph; font.pixelSize: 22; w: 500 }
        Column { visible: tb.icon === "list"; anchors.centerIn: parent; spacing: 4
            Repeater { model: 3; Rectangle { width: 18; height: 2.4; radius: 1.2; color: Theme.ink } } }
        Grid { visible: tb.icon === "grid"; anchors.centerIn: parent; columns: 2; spacing: 3
            Repeater { model: 4; Rectangle { width: 8; height: 8; radius: 2.5; color: Theme.ink } } }
        Item { visible: tb.icon === "eye" || tb.icon === "eyeoff"; anchors.centerIn: parent; width: 24; height: 24
            Rectangle { anchors.centerIn: parent; width: 22; height: 14; radius: 7; color: "transparent"; border.width: 2; border.color: Theme.ink }
            Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Theme.ink }
            Rectangle { visible: tb.icon === "eyeoff"; anchors.centerIn: parent; width: 2.2; height: 26; radius: 1.1; rotation: 45; color: Theme.ink } }
        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; enabled: tb.enabled2; onClicked: tb.clicked() }
    }
    // the ring around something a drag is over
    component DropRing: Rectangle {
        property bool on: false
        anchors.fill: parent; radius: 16; color: Theme.acc; opacity: on ? .22 : 0
        border.color: Theme.acc; border.width: on ? 2 : 0
        Behavior on opacity { NumberAnimation { duration: 90 } }
    }

    // ---- sidebar ----
    Rectangle {
        id: side
        width: win.compact ? 64 : (win.width < 800 ? 170 : 210); height: parent.height
        color: Theme.sidebg
        Behavior on color { ColorAnimation { duration: 300 } }
        Column {
            x: 12; y: 14; width: parent.width - 24; spacing: 3
            T { visible: !win.compact; x: 10; text: "Places"; font.pixelSize: 13; w: 560; color: Theme.i55 }
            Repeater {
                model: win.places
                Item {
                    required property var modelData
                    width: parent.width; height: 42
                    readonly property bool cur: win.cwd === modelData.path
                    Rectangle { anchors.fill: parent; radius: 14; color: Theme.acc; opacity: cur ? 1 : (pma.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 120 } } }
                    DropRing { on: pdrop.containsDrag }
                    Image { x: win.compact ? (parent.width - 20) / 2 : 12; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sourceSize: Qt.size(60, 60)
                        source: "file:///usr/share/smof/icons/folder" + (cur ? (Theme.dark ? "" : "-d") : Theme.sfx) + ".svg" }
                    T { visible: !win.compact; x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 54; elide: Text.ElideRight; text: modelData.name; w: cur ? 600 : 460; font.pixelSize: 16; color: cur ? Theme.onacc : Theme.ink }
                    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(modelData.path) }
                    DropArea { id: pdrop; anchors.fill: parent; onDropped: (d) => win.dropOn(modelData.path, d) }
                }
            }
            Item { visible: win.drives.length > 0; width: 1; height: 10 }
            T { visible: win.drives.length > 0 && !win.compact; x: 10; text: "Devices"; font.pixelSize: 13; w: 560; color: Theme.i55 }
            Repeater {
                model: win.drives
                Item {
                    required property var modelData
                    width: parent.width; height: 52
                    readonly property bool cur: modelData.mount !== "" && (win.cwd === modelData.mount || win.cwd.indexOf(modelData.mount + "/") === 0)
                    readonly property bool busy: win.busyDev === modelData.dev
                    Rectangle { anchors.fill: parent; radius: 14; color: Theme.acc; opacity: cur ? 1 : (dma.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 120 } } }
                    DropRing { on: ddrop.containsDrag && modelData.mount !== "" }
                    Rectangle { x: win.compact ? (parent.width - 22) / 2 : 12; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 16; radius: 5; color: "transparent"; border.width: 2; border.color: cur ? Theme.onacc : Theme.ink
                        Rectangle { x: 4; y: 9; width: 4; height: 2; radius: 1; color: cur ? Theme.onacc : Theme.ink } }
                    Column { visible: !win.compact; x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44 - (modelData.mount !== "" && !modelData.system ? 40 : 8); spacing: 0
                        T { width: parent.width; elide: Text.ElideRight; text: modelData.name; font.pixelSize: 15; w: cur ? 600 : 460; color: cur ? Theme.onacc : Theme.ink }
                        T { width: parent.width; elide: Text.ElideRight; font.pixelSize: 12; color: cur ? Theme.onacc : Theme.i55
                            text: busy ? "Working..." : (win.fmtSize(modelData.size) + (modelData.mount === "" ? "  Not mounted" : "")) } }
                    MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; onClicked: win.openDrive(modelData) }
                    DropArea { id: ddrop; anchors.fill: parent; enabled: modelData.mount !== ""; onDropped: (d) => win.dropOn(modelData.mount, d) }
                    Item { visible: modelData.mount !== "" && !modelData.system && !win.compact; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32
                        Rectangle { anchors.fill: parent; radius: 16; color: cur ? Theme.onacc : Theme.ink; opacity: ema.containsMouse ? .18 : 0 }
                        T { anchors.centerIn: parent; text: "⏏"; font.pixelSize: 18; color: cur ? Theme.onacc : Theme.ink }
                        MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; onClicked: win.ejectDrive(modelData) } }
                }
            }
        }
    }

    // ---- toolbar ----
    Item {
        id: bar
        x: side.width; width: parent.width - side.width; height: 62
        Row {
            id: navRow
            x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 2
            TBtn { glyph: "‹"; enabled2: win.back.length > 0; onClicked: win.goBack() }
            TBtn { glyph: "›"; enabled2: win.fwd.length > 0; onClicked: win.goFwd() }
            TBtn { glyph: "↑"; enabled2: win.cwd !== "/"; onClicked: win.goUp() }
        }
        // search
        Rectangle {
            id: sbox
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            visible: !win.compact; width: win.compact ? 0 : (win.width < 820 ? 110 : 160); height: 40; radius: 20; color: Theme.cardbg
            T { visible: sin.text === ""; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Search"; font.pixelSize: 15; color: Theme.i5 }
            TextInput { id: sin; x: 16; width: parent.width - 32; anchors.verticalCenter: parent.verticalCenter; font.family: "Google Sans Flex"; font.pixelSize: 15; color: Theme.ink; clip: true
                onTextChanged: win.filter = text }
        }
        // view toggle and hidden files
        Row {
            id: tools
            anchors.right: sbox.visible ? sbox.left : parent.right; anchors.rightMargin: sbox.visible ? 6 : 8; anchors.verticalCenter: parent.verticalCenter; spacing: 0
            TBtn { icon: win.grid ? "list" : "grid"; onClicked: win.grid = !win.grid }
            TBtn { icon: win.hidden ? "eye" : "eyeoff"; onClicked: { win.hidden = !win.hidden; win.refresh() } }
        }
        // path as clickable parts, always scrolled to the end so the current folder is visible
        Rectangle {
            id: pathbox
            x: navRow.x + navRow.width + 12; anchors.verticalCenter: parent.verticalCenter
            width: Math.max(80, tools.x - x - 8); height: 40; radius: 20; color: Theme.cardbg; clip: true
            ListView {
                id: crumbList
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                orientation: ListView.Horizontal
                interactive: false
                model: win.crumbs()
                onModelChanged: Qt.callLater(function () { crumbList.positionViewAtEnd() })
                onCountChanged: Qt.callLater(function () { crumbList.positionViewAtEnd() })
                onWidthChanged: Qt.callLater(function () { crumbList.positionViewAtEnd() })
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: chev.width + cbtn.width; height: crumbList.height
                    Item {
                        id: chev
                        width: index > 0 ? 14 : 0; height: parent.height
                        T { visible: index > 0; anchors.centerIn: parent; text: "›"; font.pixelSize: 18; color: Theme.i5 }
                    }
                    Item {
                        id: cbtn
                        x: chev.width
                        width: ct.implicitWidth + 16; height: parent.height
                        Rectangle { anchors.fill: parent; anchors.topMargin: 4; anchors.bottomMargin: 4; radius: 14; color: Theme.acc; opacity: cma.containsMouse || cdrop.containsDrag ? .2 : 0 }
                        T { id: ct; anchors.centerIn: parent; text: modelData.name === "/" ? "Computer" : modelData.name; font.pixelSize: 16; w: index === win.crumbs().length - 1 ? 600 : 460 }
                        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(modelData.path) }
                        DropArea { id: cdrop; anchors.fill: parent; onDropped: (d) => win.dropOn(modelData.path, d) }
                    }
                }
            }
            Rectangle {
                visible: crumbList.contentWidth > crumbList.width
                x: 0; width: 34; height: parent.height
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.cardbg }
                    GradientStop { position: 1; color: "transparent" } }
            }
        }
    }

    // ---- the trash says what it is and offers to empty itself ----
    Item {
        visible: win.banner > 0
        x: side.width + 14; y: bar.height + 2; width: parent.width - side.width - 28; height: win.banner - 6
        Rectangle { anchors.fill: parent; radius: 18; color: Theme.errbg
            T { x: 18; anchors.verticalCenter: parent.verticalCenter; width: parent.width - ebt.width - 56; elide: Text.ElideRight; font.pixelSize: 15; color: Theme.errfg
                text: win.items.length + (win.items.length === 1 ? " item" : " items") + " in the Trash. They stay here until you empty it." }
            Item { id: ebt; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; width: ebl.implicitWidth + 28; height: 32
                Rectangle { anchors.fill: parent; radius: 16; color: Theme.errfg; Rectangle { anchors.fill: parent; radius: 16; color: "#000000"; opacity: ebm.pressed ? .18 : 0 } }
                T { id: ebl; anchors.centerIn: parent; text: "Empty Trash"; font.pixelSize: 14; w: 650; color: Theme.errbg }
                MouseArea { id: ebm; anchors.fill: parent; onClicked: win.askEmpty() } } }
    }

    // ---- content ----
    Item {
        id: content
        x: side.width; y: bar.height + win.banner; width: parent.width - side.width; height: parent.height - bar.height - win.banner - 38
        clip: true
        focus: true

        // empty and error states
        Item {
            visible: win.err !== "" && !win.admin
            anchors.horizontalCenter: parent.horizontalCenter; y: parent.height / 2 + 28; width: abtn.width; height: 42
            z: 20
            Rectangle { id: abtn; width: at.implicitWidth + 40; height: 42; radius: 21; color: Theme.acc
                Rectangle { anchors.fill: parent; radius: 21; color: "#000000"; opacity: ama.pressed ? .18 : 0 }
                T { id: at; anchors.centerIn: parent; text: "Open as administrator"; font.pixelSize: 16; w: 600; color: Theme.onacc }
                MouseArea { id: ama; anchors.fill: parent; onClicked: win.goAdmin() } }
        }
        T { visible: win.asking; anchors.centerIn: parent; text: "Waiting for permission..."; font.pixelSize: 18; color: Theme.i55 }
        T { visible: win.shown.length === 0 && !win.asking; anchors.centerIn: parent; text: win.err !== "" ? win.err : (win.filter !== "" ? "No matches" : (win.inTrash ? "Trash is empty" : "This folder is empty")); font.pixelSize: 18; color: Theme.i55 }

        // empty space: click clears the selection, right click opens the folder menu; a drop here goes into this folder
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => { win.setSel([]); win.renaming = ""; if (m.button === Qt.RightButton) { var p = mapToItem(win.contentItem, m.x, m.y); win.openCtx(p.x, p.y, null) } } }
        DropArea { anchors.fill: parent; onDropped: (d) => win.dropOn(win.cwd, d) }

        GridView {
            id: gv
            visible: win.grid
            anchors.fill: parent; anchors.margins: 10
            cellWidth: 124; cellHeight: 128
            model: win.grid ? win.shown : []
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: gcell
                required property var modelData
                width: gv.cellWidth; height: gv.cellHeight
                readonly property bool cur: win.isSel(modelData.name)
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                Drag.proposedAction: Qt.MoveAction
                Drag.mimeData: ({ "text/uri-list": win.dragUris })
                Rectangle { anchors.fill: parent; anchors.margins: 4; radius: 18; color: Theme.acc; opacity: gcell.cur ? .22 : (gma.containsMouse ? .09 : 0); Behavior on opacity { NumberAnimation { duration: 100 } } }
                DropRing { on: gdrop.containsDrag && modelData.dir; anchors.margins: 4 }
                Item {
                    x: (parent.width - 60) / 2; y: 12; width: 60; height: 60
                    Image { visible: modelData.dir; anchors.fill: parent; sourceSize: Qt.size(120, 120); source: "file:///usr/share/smof/icons/folder" + Theme.sfx + ".svg"; fillMode: Image.PreserveAspectFit; opacity: .9 }
                    Rectangle { visible: !modelData.dir && !(win.isImage(modelData.name) && modelData.size < 60000000); anchors.centerIn: parent; width: 46; height: 56; radius: 10; color: Theme.moonbg
                        T { visible: win.extOf(modelData.name) !== ""; anchors.centerIn: parent; text: win.extOf(modelData.name); font.pixelSize: 13; w: 700; color: Theme.acc }
                        Column { visible: win.extOf(modelData.name) === ""; anchors.centerIn: parent; spacing: 6
                            Repeater { model: 3; Rectangle { required property int index; width: index === 2 ? 14 : 24; height: 3; radius: 1.5; color: Theme.acc; opacity: .7 } } } }
                    Image { visible: !modelData.dir && win.isImage(modelData.name) && modelData.size < 60000000; anchors.fill: parent; asynchronous: true; fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(120, 120); source: visible ? "file://" + win.pathOf(modelData.name) : "" }
                }
                T { visible: win.renaming !== modelData.name; x: 8; y: 82; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.pixelSize: 14; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight }
                TextInput { id: gren; visible: win.renaming === modelData.name; x: 8; y: 82; width: parent.width - 16; horizontalAlignment: TextInput.AlignHCenter; font.family: "Google Sans Flex"; font.pixelSize: 14; color: Theme.ink; text: modelData.name; selectByMouse: true
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                    Keys.onReturnPressed: win.doRename(text); Keys.onEscapePressed: win.renaming = ""
                    onActiveFocusChanged: if (!activeFocus && win.renaming === modelData.name) win.doRename(text) }
                MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) { if (!win.isSel(modelData.name)) { win.setSel([modelData.name], modelData.name); win.anchorName = modelData.name }
                            var p = gma.mapToItem(win.contentItem, m.x, m.y); win.openCtx(p.x, p.y, modelData) }
                        else win.clickItem(modelData.name, m.modifiers) }
                    onDoubleClicked: win.openItem(modelData) }
                DropArea { id: gdrop; anchors.fill: parent; enabled: modelData.dir && !gcell.cur; onDropped: (d) => win.dropOn(win.pathOf(modelData.name), d) }
                DragHandler {
                    id: gdh
                    target: null
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: {
                        if (active) { win.beginDrag(modelData.name); gcell.grabToImage(function (r) { gcell.Drag.imageSource = r.url; gcell.Drag.active = true }) }
                        else gcell.Drag.active = false
                    }
                }
                Drag.onDragFinished: gcell.Drag.active = false
            }
        }

        ListView {
            id: lv
            visible: !win.grid
            anchors.fill: parent; anchors.margins: 10
            model: !win.grid ? win.shown : []
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            header: Item { width: lv.width; height: 30
                T { x: 52; text: "Name"; font.pixelSize: 13; color: win.sortBy === "name" ? Theme.acc : Theme.i55; w: 560
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { if (win.sortBy === "name") win.sortDesc = !win.sortDesc; else { win.sortBy = "name"; win.sortDesc = false } } } }
                T { anchors.right: parent.right; anchors.rightMargin: 190; text: "Size"; font.pixelSize: 13; color: win.sortBy === "size" ? Theme.acc : Theme.i55; w: 560
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { if (win.sortBy === "size") win.sortDesc = !win.sortDesc; else { win.sortBy = "size"; win.sortDesc = false } } } }
                T { anchors.right: parent.right; anchors.rightMargin: 24; text: "Modified"; font.pixelSize: 13; color: win.sortBy === "date" ? Theme.acc : Theme.i55; w: 560
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { if (win.sortBy === "date") win.sortDesc = !win.sortDesc; else { win.sortBy = "date"; win.sortDesc = false } } } } }
            delegate: Item {
                id: lrow
                required property var modelData
                width: lv.width; height: 46
                readonly property bool cur: win.isSel(modelData.name)
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                Drag.proposedAction: Qt.MoveAction
                Drag.mimeData: ({ "text/uri-list": win.dragUris })
                Rectangle { anchors.fill: parent; anchors.topMargin: 1; anchors.bottomMargin: 1; radius: 14; color: Theme.acc; opacity: lrow.cur ? .22 : (lma.containsMouse ? .09 : 0); Behavior on opacity { NumberAnimation { duration: 100 } } }
                DropRing { on: ldrop.containsDrag && modelData.dir; anchors.topMargin: 1; anchors.bottomMargin: 1 }
                Item { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28
                    Image { visible: modelData.dir; anchors.fill: parent; sourceSize: Qt.size(60, 60); source: "file:///usr/share/smof/icons/folder" + Theme.sfx + ".svg"; fillMode: Image.PreserveAspectFit; opacity: .9 }
                    Rectangle { visible: !modelData.dir; anchors.centerIn: parent; width: 22; height: 28; radius: 6; color: Theme.moonbg
                        T { visible: win.extOf(modelData.name) === ""; anchors.centerIn: parent; text: "≡"; font.pixelSize: 18; color: Theme.acc } } }
                T { visible: win.renaming !== modelData.name; x: 52; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52 - 280; elide: Text.ElideRight; text: modelData.name; font.pixelSize: 16 }
                TextInput { id: lren; visible: win.renaming === modelData.name; x: 52; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52 - 280; font.family: "Google Sans Flex"; font.pixelSize: 16; color: Theme.ink; text: modelData.name; selectByMouse: true
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                    Keys.onReturnPressed: win.doRename(text); Keys.onEscapePressed: win.renaming = ""
                    onActiveFocusChanged: if (!activeFocus && win.renaming === modelData.name) win.doRename(text) }
                T { anchors.right: parent.right; anchors.rightMargin: 190; anchors.verticalCenter: parent.verticalCenter; text: modelData.dir ? "" : win.fmtSize(modelData.size); font.pixelSize: 14; color: Theme.i62 }
                T { anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; text: win.fmtDate(modelData.mtime); font.pixelSize: 14; color: Theme.i62 }
                MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) { if (!win.isSel(modelData.name)) { win.setSel([modelData.name], modelData.name); win.anchorName = modelData.name }
                            var p = lma.mapToItem(win.contentItem, m.x, m.y); win.openCtx(p.x, p.y, modelData) }
                        else win.clickItem(modelData.name, m.modifiers) }
                    onDoubleClicked: win.openItem(modelData) }
                DropArea { id: ldrop; anchors.fill: parent; enabled: modelData.dir && !lrow.cur; onDropped: (d) => win.dropOn(win.pathOf(modelData.name), d) }
                DragHandler {
                    id: ldh
                    target: null
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: {
                        if (active) { win.beginDrag(modelData.name); lrow.grabToImage(function (r) { lrow.Drag.imageSource = r.url; lrow.Drag.active = true }) }
                        else lrow.Drag.active = false
                    }
                }
                Drag.onDragFinished: lrow.Drag.active = false
            }
        }

        Keys.onPressed: (e) => {
            if (win.renaming !== "") return
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.openItem(win.selItem()); e.accepted = true }
            else if (e.key === Qt.Key_Delete) { if (win.inTrash) win.askPurgeSel(); else win.trashSel(); e.accepted = true }
            else if (e.key === Qt.Key_F2 && win.sel !== "") { win.renaming = win.sel; e.accepted = true }
            else if (e.key === Qt.Key_Escape) { win.closeCtx(); win.propsInfo = null; win.setSel([]); e.accepted = true }
            else if (e.key === Qt.Key_Backspace) { if (win.selNames().length > 0) { if (win.inTrash) win.askPurgeSel(); else win.trashSel() } else win.goUp(); e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_A) { win.selectAll(); e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_C) { win.copySel(false); e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_X) { win.copySel(true); e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_V) { win.pasteHere(); e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_H) { win.hidden = !win.hidden; win.refresh(); e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier) && e.key === Qt.Key_N) { win.newFolder(); e.accepted = true }
        }
    }

    // ---- status line ----
    Rectangle {
        x: side.width; y: parent.height - 38; width: parent.width - side.width; height: 38
        color: "transparent"
        Rectangle { width: parent.width; height: 1; color: Theme.i12 }
        Item { visible: win.inTrash && win.items.length > 0 && !win.admin; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; width: et.implicitWidth + 26; height: 26
            Rectangle { anchors.fill: parent; radius: 13; color: Theme.errbg; Rectangle { anchors.fill: parent; radius: 13; color: Theme.errfg; opacity: ema2.containsMouse ? .14 : 0 } }
            T { id: et; anchors.centerIn: parent; text: "Empty Trash"; font.pixelSize: 13; w: 600; color: Theme.errfg }
            MouseArea { id: ema2; anchors.fill: parent; hoverEnabled: true; onClicked: win.askEmpty() } }
        Row { visible: win.admin; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Rectangle { height: 26; width: adt.implicitWidth + 20; radius: 13; color: Theme.warnbg
                T { id: adt; anchors.centerIn: parent; text: "Administrator"; font.pixelSize: 13; w: 600; color: Theme.warnfg } }
            Item { width: lt2.implicitWidth + 20; height: 26
                Rectangle { anchors.fill: parent; radius: 13; color: Theme.moonbg; Rectangle { anchors.fill: parent; radius: 13; color: Theme.acc; opacity: lma2.containsMouse ? .14 : 0 } }
                T { id: lt2; anchors.centerIn: parent; text: "Leave"; font.pixelSize: 13; w: 560; color: Theme.acc }
                MouseArea { id: lma2; anchors.fill: parent; hoverEnabled: true; onClicked: win.leaveAdmin() } } }
        T { x: 18; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 14; color: Theme.i62
            text: win.note !== "" ? win.note : (win.selNames().length > 1 ? win.selNames().length + " selected" : (win.sel !== "" ? win.sel + (win.selItem() && !win.selItem().dir ? "  " + win.fmtSize(win.selItem().size) : "") : win.shown.length + (win.shown.length === 1 ? " item" : " items"))) }
    }

    // ---- picture viewer ----
    Item {
        id: viewer
        visible: win.viewing !== ""
        anchors.fill: parent
        focus: visible
        onVisibleChanged: if (visible) forceActiveFocus(); else content.forceActiveFocus()
        Keys.onEscapePressed: win.viewing = ""
        Keys.onLeftPressed: win.stepPicture(-1)
        Keys.onRightPressed: win.stepPicture(1)
        Rectangle { anchors.fill: parent; color: "#0C0A14"; opacity: .94 }
        MouseArea { anchors.fill: parent; onClicked: win.viewing = "" }
        Image {
            id: vimg
            anchors.fill: parent; anchors.margins: 56
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            autoTransform: true
            sourceSize: Qt.size(2400, 2400)
            source: win.viewing !== "" ? "file://" + win.pathOf(win.viewing) : ""
            MouseArea { anchors.fill: parent; onClicked: {} }
        }
        T { visible: vimg.status === Image.Loading; anchors.centerIn: parent; text: "Loading..."; font.pixelSize: 18; color: "#CCFFFFFF" }
        T { visible: vimg.status === Image.Error; anchors.centerIn: parent; text: "This picture could not be shown"; font.pixelSize: 18; color: "#CCFFFFFF" }
        T { x: 22; y: 14; text: win.viewing; font.pixelSize: 15; color: "#CCFFFFFF" }
        // close, previous, next
        Item { x: parent.width - 54; y: 8; width: 40; height: 40
            Rectangle { anchors.fill: parent; radius: 20; color: "#FFFFFF"; opacity: cx.containsMouse ? .2 : .08 }
            T { anchors.centerIn: parent; text: "\u2715"; font.pixelSize: 18; color: "#FFFFFF" }
            MouseArea { id: cx; anchors.fill: parent; hoverEnabled: true; onClicked: win.viewing = "" } }
        Item { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 44; visible: win.pictures().length > 1
            Rectangle { anchors.fill: parent; radius: 22; color: "#FFFFFF"; opacity: lx.containsMouse ? .2 : .08 }
            T { anchors.centerIn: parent; text: "\u2039"; font.pixelSize: 28; color: "#FFFFFF" }
            MouseArea { id: lx; anchors.fill: parent; hoverEnabled: true; onClicked: win.stepPicture(-1) } }
        Item { x: parent.width - 54; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 44; visible: win.pictures().length > 1
            Rectangle { anchors.fill: parent; radius: 22; color: "#FFFFFF"; opacity: rx.containsMouse ? .2 : .08 }
            T { anchors.centerIn: parent; text: "\u203A"; font.pixelSize: 28; color: "#FFFFFF" }
            MouseArea { id: rx; anchors.fill: parent; hoverEnabled: true; onClicked: win.stepPicture(1) } }
    }

    // ---- properties ----
    Item {
        visible: win.propsInfo !== null
        anchors.fill: parent
        MouseArea { anchors.fill: parent; onClicked: win.propsInfo = null }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: .35 }
        Rectangle {
            anchors.centerIn: parent
            width: 420; height: pcol.implicitHeight + 40; radius: 28; color: Theme.menubg; border.color: Theme.glassBorder
            MouseArea { anchors.fill: parent }
            Column {
                id: pcol
                x: 24; y: 22; width: parent.width - 48; spacing: 10
                T { text: win.propsInfo ? win.propsInfo.name : ""; font.pixelSize: 22; w: 640; width: parent.width; elide: Text.ElideMiddle }
                Repeater {
                    model: win.propsInfo ? [
                        ["Kind", win.propsInfo.kind + (win.propsInfo.mime ? "  " + win.propsInfo.mime : "")],
                        ["Size", win.fmtSize(win.propsInfo.size) + (win.propsInfo.kind === "Folder" ? "  in " + win.propsInfo.files + " files" : "")],
                        ["Modified", win.fmtDate(win.propsInfo.mtime)],
                        ["Where", win.dirOf(win.propsInfo.path)],
                        ["Permissions", win.propsInfo.mode],
                        ["Owner", win.propsInfo.owner + ":" + win.propsInfo.group]
                    ] : []
                    Row { required property var modelData; width: pcol.width; spacing: 12
                        T { width: 100; text: modelData[0]; font.pixelSize: 15; color: Theme.i55 }
                        T { width: pcol.width - 112; text: modelData[1]; font.pixelSize: 15; wrapMode: Text.WrapAnywhere } }
                }
                Item { width: parent.width; height: 8 }
                Item { anchors.right: parent.right; width: ok2.implicitWidth + 40; height: 42
                    Rectangle { anchors.fill: parent; radius: 21; color: Theme.acc }
                    T { id: ok2; anchors.centerIn: parent; text: "Close"; font.pixelSize: 16; w: 600; color: Theme.onacc }
                    MouseArea { anchors.fill: parent; onClicked: win.propsInfo = null } }
            }
        }
    }

    // ---- deleting for good: asks first ----
    Item {
        visible: win.purgeAsk !== null
        anchors.fill: parent; z: 150
        MouseArea { anchors.fill: parent; onClicked: win.purgeAsk = null }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: .4 }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 40); height: pq.implicitHeight + 48; radius: 30; color: Theme.menubg; border.color: Theme.glassBorder
            MouseArea { anchors.fill: parent }
            Column { id: pq; x: 26; y: 24; width: parent.width - 52; spacing: 12
                T { width: parent.width; wrapMode: Text.Wrap; font.pixelSize: 22; w: 650
                    text: win.purgeAsk ? (win.purgeAsk.all ? "Empty the Trash?" : "Delete for good?") : "" }
                T { width: parent.width; wrapMode: Text.Wrap; font.pixelSize: 15; color: Theme.i62
                    text: win.purgeAsk ? ((win.purgeAsk.count === 1 ? "1 item" : win.purgeAsk.count + " items") + " will be deleted and cannot be brought back.") : "" }
                Row { spacing: 10; anchors.right: parent.right
                    Item { width: pc.implicitWidth + 40; height: 42
                        Rectangle { anchors.fill: parent; radius: 21; color: Theme.moonbg }
                        T { id: pc; anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 16; w: 600; color: Theme.acc }
                        MouseArea { anchors.fill: parent; onClicked: win.purgeAsk = null } }
                    Item { width: pd.implicitWidth + 40; height: 42
                        Rectangle { anchors.fill: parent; radius: 21; color: Theme.errfg }
                        T { id: pd; anchors.centerIn: parent; text: win.purgeAsk && win.purgeAsk.all ? "Empty Trash" : "Delete"; font.pixelSize: 16; w: 650; color: Theme.errbg }
                        MouseArea { anchors.fill: parent; onClicked: win.doPurge() } } }
            }
        }
    }

    // a click anywhere in the window closes an open context menu
    MouseArea { anchors.fill: parent; enabled: ctx.visible; acceptedButtons: Qt.AllButtons; z: 100; onPressed: win.closeCtx() }
}
