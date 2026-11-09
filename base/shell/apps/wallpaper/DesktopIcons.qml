import Quickshell
import Quickshell.Io
import QtQuick

// the things on the desktop: whatever is in ~/Desktop, as icons on a grid. Drag to move, double click to open, right click for a menu.
// New icons start in the right hand column going down, like on a Mac. Positions are kept in ~/.config/smof-desktop.json.
Item {
    id: di
    readonly property string home: Quickshell.env("HOME")
    readonly property int cw: 116
    readonly property int ch: 124
    readonly property real topPad: 84
    readonly property real botPad: 132
    property var items: []
    property var pos: ({})
    property var sel: []
    signal menuRequested(real x, real y, var entries)
    // the icon that follows the pointer while one is dragged, drawn by the wallpaper app in a window above the dock
    property bool ghostOn: false
    property bool holding: false          // a button is down on a dragged icon
    function anyPressed() { return holding }
    property real ghostX: 0
    property real ghostY: 0
    property string ghostSrc: ""
    property string ghostLabel: ""

    // ---- the folder ----
    Process {
        id: lsP
        command: ["/usr/local/bin/smof-desktop", "list"]
        stdout: StdioCollector { onStreamFinished: { try { di.items = JSON.parse(text).items } catch (e) {} } }
    }
    function refresh() { lsP.running = true }
    Timer { interval: 2000; repeat: true; running: true; triggeredOnStart: true; onTriggered: di.refresh() }
    function sh(args) { Quickshell.execDetached({ command: args, workingDirectory: home }) }

    // ---- remembered places ----
    FileView {
        id: pf
        path: di.home + "/.config/smof-desktop.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { var o = JSON.parse(text()); if (o && typeof o === "object") di.pos = o } catch (e) {} }
    }
    function savePos(p) { di.pos = p; pf.setText(JSON.stringify(p)) }

    // ---- the grid ----
    readonly property real ox: ((width - 16 - cw) % cw + cw) % cw
    readonly property int rows: Math.max(1, Math.floor((height - topPad - botPad) / ch))
    function snapX(x) { return Math.max(ox, Math.min(width - cw - 8, ox + Math.round((x - ox) / cw) * cw)) }
    function snapY(y) { return Math.max(topPad, Math.min(topPad + (rows - 1) * ch, topPad + Math.round((y - topPad) / ch) * ch)) }
    function cellKey(x, y) { return Math.round((x - ox) / cw) + "," + Math.round((y - topPad) / ch) }
    // where each item sits: its saved place, or the first free slot counted from the top right
    readonly property var placed: {
        var out = {}, used = {}
        var names = items.map(function (i) { return i.name })
        for (var i = 0; i < names.length; i++) {
            var p = pos[names[i]]
            if (p) { var sx = snapX(p.x), sy = snapY(p.y); out[names[i]] = { x: sx, y: sy }; used[cellKey(sx, sy)] = true }
        }
        var k = 0
        for (var j = 0; j < names.length; j++) {
            if (out[names[j]]) continue
            while (true) {
                var col = Math.floor(k / rows), row = k % rows
                var x = width - cw - 16 - col * cw, y = topPad + row * ch
                k++
                if (x < 0) { x = 0 }
                if (!used[cellKey(x, y)]) { out[names[j]] = { x: x, y: y }; used[cellKey(x, y)] = true; break }
            }
        }
        return out
    }
    // the free cell closest to a wish, ignoring the items in `skip`
    function freeCell(wx, wy, skip, extra) {
        var used = {}
        if (extra) for (var q = 0; q < extra.length; q++) used[cellKey(extra[q].x, extra[q].y)] = true
        for (var n in placed) if (skip.indexOf(n) < 0) used[cellKey(placed[n].x, placed[n].y)] = true
        var bx = snapX(wx), by = snapY(wy)
        for (var r = 0; r < 40; r++) {
            for (var dx = -r; dx <= r; dx++) for (var dy = -r; dy <= r; dy++) {
                if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue
                var x = bx + dx * cw, y = by + dy * ch
                if (x < ox - 1 || x > width - cw - 7 || y < topPad - 1 || y > topPad + (rows - 1) * ch + 1) continue
                if (!used[cellKey(x, y)]) return { x: x, y: y }
            }
        }
        return { x: bx, y: by }
    }
    function moveTo(name, wx, wy) {
        var c = freeCell(wx, wy, [name])
        var p = Object.assign({}, pos)
        // every item gets a fixed place once one is moved, so the others do not jump around
        for (var n in placed) if (!p[n]) p[n] = placed[n]
        p[name] = c
        savePos(p)
    }
    function cleanUp() { savePos({}) }

    // ---- things coming in: files dropped from Files or the dock ----
    function dropped(paths, x, y, copy) {
        if (paths.length === 0) return
        var p = Object.assign({}, pos)
        for (var n in placed) if (!p[n]) p[n] = placed[n]
        var extra = []
        for (var i = 0; i < paths.length; i++) {
            var nm = paths[i].split("/").pop()
            var cell = freeCell(x, y, [nm], extra)
            p[nm] = cell; extra.push(cell)
        }
        savePos(p)
        sh(["/usr/local/bin/smof-fileops", copy ? "copy" : "move", home + "/Desktop"].concat(paths))
        refT.restart()
    }
    Timer { id: refT; interval: 700; onTriggered: di.refresh() }
    // a launcher for an app from the dock, dropped at the pointer
    property real addX: 0
    property real addY: 0
    Process {
        id: addP
        stdout: StdioCollector { onStreamFinished: {
            try { var n = JSON.parse(text).name; var p = Object.assign({}, di.pos); for (var k in di.placed) if (!p[k]) p[k] = di.placed[k]; p[n] = di.freeCell(di.addX, di.addY, [n], []); di.savePos(p) } catch (e) {}
            di.refresh() } }
    }
    function addApp(spec, x, y) {
        try {
            var s = JSON.parse(spec)
            addX = x; addY = y
            addP.command = ["/usr/local/bin/smof-desktop", "mklauncher", s.name, s.icon].concat(s.cmd)
            addP.running = true
        } catch (e) {}
    }

    // ---- selection and actions ----
    function clearSel() { sel = [] }
    // while an icon is dragged near the bottom the dock shows where it would go
    Timer { interval: 400; repeat: true; running: di.ghostOn; onTriggered: { if (!di.anyPressed()) { di.ghostOn = false; di.hoverStop() } } }
    property bool nearDock: false
    property var hoverArgs: null
    function sendHover() { var a = di.hoverArgs; if (a) di.sh(["/usr/local/bin/smof-ipc", "dock", "dock", "hover", a.kind, String(a.x), String(a.y)]) }
    // the position is sent again and again while the icon is held over the dock, so the dock keeps the highlight
    Timer { id: hoverT; interval: 120; repeat: true; running: di.nearDock; onTriggered: di.sendHover() }
    function hoverDock(it, x, y) {
        if (y >= height - 130) {
            var first = !nearDock
            nearDock = true
            hoverArgs = { kind: it.kind === "app" ? "app" : "file", x: Math.round(x), y: Math.round(y) }
            if (first) sendHover()
        } else if (nearDock) hoverStop()
    }
    function hoverStop() {
        if (!nearDock) return
        nearDock = false; hoverArgs = null
        sh(["/usr/local/bin/smof-ipc", "dock", "dock", "hoverend"])
    }
    function toDock(it, x, y) {
        var chosen = items.filter(function (i) { return sel.indexOf(i.name) >= 0 })
        if (chosen.length === 0 || sel.indexOf(it.name) < 0) chosen = [it]
        var spec = JSON.stringify({ kind: chosen.length === 1 && chosen[0].kind === "app" ? "app" : "file", name: chosen[0].label, exec: chosen[0].exec || "",
            paths: chosen.map(function (i) { return i.path }) })
        sh(["/usr/local/bin/smof-ipc", "dock", "dock", "dropat", spec, String(Math.round(x)), String(Math.round(y))])
    }
    function openItem(it) {
        if (it.kind === "app") sh(["/usr/local/bin/smof-desktop", "launch", it.path])
        else if (it.dir) sh(["/usr/local/bin/smof-files", it.path])
        else sh(["/usr/local/bin/smof-fileops", "open", it.path])
    }
    function trashSel() {
        var ps = items.filter(function (i) { return sel.indexOf(i.name) >= 0 }).map(function (i) { return i.path })
        if (ps.length) sh(["/usr/local/bin/smof-fileops", "trash"].concat(ps))
        sel = []; refT.restart()
    }
    function itemMenu(it) {
        var m = [ { label: "Open", run: function () { di.openItem(it) } } ]
        if (it.dir) m.push({ label: "Show in Files", run: function () { di.sh(["/usr/local/bin/smof-files", it.path]) } })
        else m.push({ label: "Show in Files", run: function () { di.sh(["/usr/local/bin/smof-files", di.home + "/Desktop"]) } })
        m.push({ sep: true })
        m.push({ label: sel.length > 1 ? "Move " + sel.length + " items to Trash" : "Move to Trash", danger: true, run: function () { di.trashSel() } })
        return m
    }

    Repeater {
        model: di.items
        Item {
            id: ic
            required property var modelData
            readonly property bool picked: di.sel.indexOf(modelData.name) >= 0
            property bool dragging: false
            property real dragX: 0
            property real dragY: 0
            width: di.cw; height: di.ch
            x: dragging ? dragX : (di.placed[modelData.name] ? di.placed[modelData.name].x : 0)
            y: dragging ? dragY : (di.placed[modelData.name] ? di.placed[modelData.name].y : 0)
            z: dragging ? 10 : 0
            opacity: dragging ? 0 : 1        // while dragged only the picture in the top layer is seen, not a second copy with its highlight
            Behavior on x { enabled: !ic.dragging; NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] } }
            Behavior on y { enabled: !ic.dragging; NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] } }
            Rectangle { anchors.fill: parent; anchors.margins: 4; radius: 20; color: Theme.acc; opacity: ic.picked ? .32 : (ma.containsMouse ? .16 : 0); Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } } }
            Item {
                x: (parent.width - 64) / 2; y: 14; width: 64; height: 64
                opacity: ic.dragging ? 0 : 1
                Image { visible: modelData.dir; anchors.fill: parent; sourceSize: Qt.size(192, 192); fillMode: Image.PreserveAspectFit
                    source: "file:///usr/share/smof/icons/folder" + Theme.sfx + ".svg" }
                Image { visible: !modelData.dir && modelData.image; anchors.fill: parent; sourceSize: Qt.size(160, 160); fillMode: Image.PreserveAspectFit; asynchronous: true
                    source: modelData.image ? "file://" + modelData.path : "" }
                Image { id: pic; visible: !modelData.dir && !modelData.image; anchors.fill: parent; sourceSize: Qt.size(192, 192); fillMode: Image.PreserveAspectFit
                    source: modelData.dir || modelData.image ? "" : (modelData.icon.charAt(0) === "/" ? "file://" + modelData.icon
                        : "file:///usr/share/icons/Papirus/64x64/" + (modelData.kind === "app" ? "apps/" : "mimetypes/") + modelData.icon + ".svg")
                    onStatusChanged: if (status === Image.Error && source.toString().indexOf("application-default-icon") < 0) source = "file:///usr/share/icons/Papirus/64x64/apps/application-default-icon.svg" }
            }
            Rectangle { x: 6; y: 84; width: parent.width - 12; height: lbl.implicitHeight + 6; radius: 10; color: Theme.acc; opacity: ic.picked ? .85 : 0 }
            // the name is white with a soft shadow so it reads on any wallpaper
            Text { visible: !ic.dragging; x: 8; y: 87; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; text: modelData.label; font.pixelSize: 14; color: "#000000"; opacity: .45; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; maximumLineCount: 2; elide: Text.ElideRight; font.family: "Google Sans Flex" }
            Text { id: lbl; visible: !ic.dragging; x: 7; y: 86; width: parent.width - 14; horizontalAlignment: Text.AlignHCenter; text: modelData.label; font.pixelSize: 14; color: ic.picked ? Theme.onacc : "#FFFFFF"; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; maximumLineCount: 2; elide: Text.ElideRight; font.family: "Google Sans Flex" }
            MouseArea {
                id: ma
                anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                property real sx: 0; property real sy: 0; property real ix: 0; property real iy: 0
                property bool moved: false
                onPressed: (m) => {
                    di.holding = true
                    var p = ic.mapToItem(di, m.x, m.y); sx = p.x; sy = p.y; ix = ic.x; iy = ic.y; moved = false
                    if (m.button === Qt.LeftButton) {
                        if (m.modifiers & Qt.ControlModifier) di.sel = ic.picked ? di.sel.filter(function (n) { return n !== modelData.name }) : di.sel.concat([modelData.name])
                        else if (!ic.picked) di.sel = [modelData.name]
                    } else if (!ic.picked) di.sel = [modelData.name]
                }
                onPositionChanged: (m) => {
                    if (!pressed || !(pressedButtons & Qt.LeftButton)) return
                    var p = ic.mapToItem(di, m.x, m.y)
                    if (!moved && Math.abs(p.x - sx) + Math.abs(p.y - sy) > 8) { moved = true; ic.dragging = true }
                    if (ic.dragging) {
                        ic.dragX = ix + p.x - sx; ic.dragY = iy + p.y - sy
                        di.ghostSrc = modelData.dir ? "file:///usr/share/smof/icons/folder" + Theme.sfx + ".svg" : (modelData.image ? "file://" + modelData.path : pic.source.toString())
                        di.ghostLabel = modelData.label
                        di.ghostX = ic.dragX; di.ghostY = ic.dragY
                        di.ghostOn = true
                        di.hoverDock(modelData, p.x, p.y)
                    }
                }
                onReleased: (m) => {
                    di.holding = false
                    if (!ic.dragging) return
                    var fx = ic.dragX, fy = ic.dragY
                    di.ghostOn = false
                    ic.dragging = false
                    var q = ic.mapToItem(di, m.x, m.y)
                    di.hoverStop()
                    // let go over the dock: the dock decides (Trash, the folder tile, or pinning an app), the icon stays where it was
                    if (q.y >= di.height - 130) di.toDock(modelData, q.x, q.y)
                    else di.moveTo(modelData.name, fx, fy)
                }
                onClicked: (m) => {
                    if (moved) return
                    if (m.button === Qt.RightButton) { var p = ic.mapToItem(di, m.x, m.y); di.menuRequested(p.x, p.y, di.itemMenu(modelData)) }
                }
                // the grab can be taken away (another window, a popup): the picture that follows the pointer must not stay behind
                onCanceled: { di.holding = false; if (ic.dragging) { ic.dragging = false; di.ghostOn = false; di.hoverStop() } }
                onPressedChanged: { if (!pressed && ic.dragging) { ic.dragging = false; di.ghostOn = false; di.hoverStop() } }
                onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) di.openItem(modelData) }
            }
        }
    }
}
