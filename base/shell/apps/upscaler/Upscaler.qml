import Quickshell
import Quickshell.Io
import QtQuick

FloatingWindow {
    id: win
    title: "Upscaler"
    readonly property real scrW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1366
    readonly property real scrH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 768
    implicitWidth: Math.min(1100, scrW - 24)
    implicitHeight: Math.min(740, scrH - 210)
    minimumSize: Qt.size(Math.min(760, implicitWidth), Math.min(520, implicitHeight))
    color: Theme.winbg
    visible: true
    onVisibleChanged: if (!visible) Qt.quit()

    readonly property string home: Quickshell.env("HOME")
    property int scaleBy: 2
    property string quality: "smart"        // fast, smart, best
    property int sel: -1                    // the row shown in the preview
    property int cur: -1                    // the row being worked on
    readonly property bool wide: width >= 900

    ListModel { id: jobs }                  // path, name, scale, mode, state (wait, run, done, error), progress, result, w, h, err
    readonly property var imgExt: ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
    function isPic(p) { var e = p.split(".").pop().toLowerCase(); return imgExt.indexOf(e) >= 0 }
    function baseName(p) { return p.split("/").pop() }
    function urlPaths(urls) { var out = []; for (var i = 0; i < urls.length; i++) { var u = String(urls[i]); if (u.indexOf("file://") === 0) { var p = decodeURIComponent(u.substring(7)); if (isPic(p)) out.push(p) } } return out }

    function addPaths(list) {
        var first = -1
        for (var i = 0; i < list.length; i++) {
            var dup = false
            for (var j = 0; j < jobs.count; j++) { var o = jobs.get(j); if (o.path === list[i] && o.scale === scaleBy && o.mode === quality && o.state !== "error") dup = true }
            if (dup) continue
            jobs.append({ path: list[i], name: baseName(list[i]), scale: scaleBy, mode: quality, state: "wait", progress: 0, result: "", w: 0, h: 0, err: "" })
            if (first < 0) first = jobs.count - 1
        }
        if (first >= 0) sel = first
        next()
    }
    function next() {
        if (cur >= 0) return
        for (var i = 0; i < jobs.count; i++) if (jobs.get(i).state === "wait") {
            cur = i
            jobs.setProperty(i, "state", "run")
            runP.command = ["/usr/local/bin/smof-upscale", jobs.get(i).path, "--scale", String(jobs.get(i).scale), "--mode", jobs.get(i).mode]
            runP.running = true
            return
        }
    }
    Process {
        id: runP
        stdout: SplitParser {
            onRead: (line) => {
                if (win.cur < 0) return
                try {
                    var o = JSON.parse(line)
                    if (o.progress !== undefined) jobs.setProperty(win.cur, "progress", o.progress)
                    else if (o.ok) { jobs.setProperty(win.cur, "state", "done"); jobs.setProperty(win.cur, "result", o.path); jobs.setProperty(win.cur, "w", o.width); jobs.setProperty(win.cur, "h", o.height); jobs.setProperty(win.cur, "progress", 100); if (win.cur === win.sel) Qt.callLater(function () { cmpV.play() }) }
                    else if (o.ok === false) { jobs.setProperty(win.cur, "state", "error"); jobs.setProperty(win.cur, "err", o.error || "It did not work") }
                } catch (e) {}
            }
        }
        onExited: {
            if (win.cur >= 0 && jobs.get(win.cur).state === "run") { jobs.setProperty(win.cur, "state", "error"); jobs.setProperty(win.cur, "err", "Stopped") }
            win.cur = -1
            win.next()
        }
    }
    function removeJob(i) {
        if (i === cur) { runP.running = false; return }
        jobs.remove(i)
        if (cur > i) cur -= 1
        if (sel >= jobs.count) sel = jobs.count - 1
        if (sel === i) sel = Math.min(i, jobs.count - 1)
    }
    function clearDone() {
        for (var i = jobs.count - 1; i >= 0; i--) { var s = jobs.get(i).state; if (s === "done" || s === "error") { jobs.remove(i); if (cur > i) cur -= 1 } }
        sel = jobs.count > 0 ? 0 : -1
    }
    function sh(args) { Quickshell.execDetached({ command: args, workingDirectory: home }) }

    // pictures to pick from: newest first from the usual folders
    property var recent: []
    Process {
        id: recentP
        command: ["python3", "-I", "-c", "import os,json\nr=[]\nh=os.path.expanduser('~')\nfor d in ('Pictures/Screenshots','Pictures','Downloads','Desktop'):\n  p=os.path.join(h,d)\n  try:\n    for n in os.listdir(p):\n      f=os.path.join(p,n)\n      if n.lower().endswith(('.png','.jpg','.jpeg','.webp','.bmp','.gif')) and os.path.isfile(f): r.append((os.path.getmtime(f),f))\n  except OSError: pass\nr.sort(reverse=True)\nprint(json.dumps([f for _,f in r[:36]]))"]
        stdout: StdioCollector { onStreamFinished: { try { win.recent = JSON.parse(text) } catch (e) {} } }
    }
    Component.onCompleted: {
        recentP.running = true
        var pre = Quickshell.env("SMOF_PICS")
        if (pre) addPaths(pre.split("|").filter(function (p) { return p !== "" && isPic(p) }))
    }

    // ---- small parts ----
    component Chip: Item {
        id: chip
        property string label: ""
        property bool on: false
        signal clicked()
        width: cht.implicitWidth + 28; height: 34
        Rectangle { anchors.fill: parent; radius: 17; color: chip.on ? Theme.acc : Theme.moonbg
            Rectangle { anchors.fill: parent; radius: 17; color: Theme.acc; opacity: chip.on ? 0 : (cma.containsMouse ? .14 : 0) } }
        T { id: cht; anchors.centerIn: parent; text: chip.label; w: 560; font.pixelSize: 15; color: chip.on ? Theme.onacc : Theme.ink }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
    }
    component Pill: Item {
        id: pl
        property string label: ""
        property bool danger: false
        signal clicked()
        width: plt.implicitWidth + 28; height: 32
        Rectangle { anchors.fill: parent; radius: 16; color: pl.danger ? Theme.errbg : Theme.moonbg
            Rectangle { anchors.fill: parent; radius: 16; color: pl.danger ? Theme.errfg : Theme.acc; opacity: pma.containsMouse ? .14 : 0 } }
        T { id: plt; anchors.centerIn: parent; text: pl.label; w: 560; font.pixelSize: 14; color: pl.danger ? Theme.errfg : Theme.acc }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: pl.clicked() }
    }
    // before and after: one picture, a slider decides how much of each is seen.
    // play() starts the reveal: the slider sweeps over the picture and the sharp version shines through behind it.
    component Compare: Item {
        id: cmp
        property string before: ""
        property string after: ""
        property real frac: 0.5
        property real wipeP: -1                  // 0 to 1 while the wipe plays, -1 otherwise
        readonly property bool wiping: wipeP >= 0
        readonly property real px0: aimg.paintedWidth > 0 ? (width - aimg.paintedWidth) / 2 : 0
        readonly property real pw: aimg.paintedWidth > 0 ? aimg.paintedWidth : width
        readonly property real edge: wiping ? px0 + pw * wipeP : width * frac
        clip: true
        function play() { wipeP = 0; playT.restart() }
        Timer { id: playT; interval: 350; onTriggered: wipeAnim.restart() }
        NumberAnimation { id: wipeAnim; target: cmp; property: "wipeP"; from: 0; to: 1; duration: 2200; easing.type: Easing.InOutSine
            onFinished: { cmp.wipeP = -1; cmp.frac = 0 } }

        Image { id: aimg; anchors.fill: parent; source: cmp.after; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: 1800; smooth: true }
        // the original, pixels left as they are: left of the slider, or right of it while it sweeps
        Item { x: cmp.wiping ? cmp.edge : 0; width: cmp.wiping ? cmp.width - cmp.edge : cmp.edge; height: parent.height; clip: true
            Image { x: cmp.wiping ? -cmp.edge : 0; width: cmp.width; height: cmp.height; source: cmp.before; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: 1800; smooth: false } }

        // slider
        Rectangle { x: cmp.edge - 1; width: 2; height: parent.height; color: "#FFFFFF"; opacity: .9 }
        Rectangle { x: cmp.edge - 18; y: cmp.height / 2 - 18; width: 36; height: 36; radius: 18; color: "#FFFFFF"
            T { anchors.centerIn: parent; text: "<>"; font.pixelSize: 14; w: 700; color: "#1B1230" } }

        // the shine that runs along the edge of the wipe
        Item { visible: cmp.wiping; x: cmp.edge - 70; y: -cmp.height * 0.15; width: 140; height: cmp.height * 1.3; rotation: 14
            Rectangle { anchors.fill: parent
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00FFFFFF" }
                    GradientStop { position: 0.45; color: "#B3FFFFFF" }
                    GradientStop { position: 0.55; color: "#B3FFFFFF" }
                    GradientStop { position: 1.0; color: "#00FFFFFF" } } } }
        Rectangle { x: 12; y: 12; width: bt.implicitWidth + 20; height: 28; radius: 14; color: "#99000000"; T { id: bt; anchors.centerIn: parent; text: "Before"; font.pixelSize: 13; color: "#FFFFFF"; w: 560 } }
        Rectangle { x: parent.width - width - 12; y: 12; width: at.implicitWidth + 20; height: 28; radius: 14; color: "#99000000"; T { id: at; anchors.centerIn: parent; text: "After"; font.pixelSize: 13; color: "#FFFFFF"; w: 560 } }
        MouseArea { anchors.fill: parent; enabled: !cmp.wiping; onPressed: (m) => cmp.frac = Math.max(0, Math.min(1, m.x / cmp.width)); onPositionChanged: (m) => { if (pressed) cmp.frac = Math.max(0, Math.min(1, m.x / cmp.width)) } }
    }

    DropArea {
        id: dropAll
        anchors.fill: parent
        onDropped: (d) => { if (d.hasUrls) { d.acceptProposedAction(); win.addPaths(win.urlPaths(d.urls)) } }
        Rectangle { anchors.fill: parent; color: Theme.acc; opacity: dropAll.containsDrag ? .12 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
    }

    Row {
        anchors.fill: parent
        // ---- left: what to add and how ----
        Item {
            id: left
            width: win.wide ? 360 : 300; height: parent.height
            Rectangle { anchors.fill: parent; color: Theme.sidebg }
            Column {
                id: leftCol
                x: 20; y: 22; width: parent.width - 40; spacing: 16
                T { text: "Upscaler"; font.pixelSize: 28; w: 700 }
                T { width: parent.width; wrapMode: Text.WordWrap; text: "Drop pictures anywhere in this window, or pick them below. They get bigger and sharper, the originals stay as they are."; font.pixelSize: 14; color: Theme.i55 }
                Column { spacing: 8; width: parent.width
                    T { text: "How much bigger"; font.pixelSize: 14; w: 600; color: Theme.i62 }
                    Row { spacing: 8
                        Repeater { model: [2, 3, 4]
                            Chip { required property int modelData; label: modelData + "x"; on: win.scaleBy === modelData; onClicked: win.scaleBy = modelData } } } }
                Column { spacing: 8; width: parent.width
                    T { text: "Quality"; font.pixelSize: 14; w: 600; color: Theme.i62 }
                    Flow { width: parent.width; spacing: 8
                        Chip { label: "Quick"; on: win.quality === "fast"; onClicked: win.quality = "fast" }
                        Chip { label: "Smart"; on: win.quality === "smart"; onClicked: win.quality = "smart" }
                        Chip { label: "Best"; on: win.quality === "best"; onClicked: win.quality = "best" } }
                    T { width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 13; color: Theme.i55
                        text: win.quality === "fast" ? "Quick: done in a second, a clean stretch with a little sharpening." : (win.quality === "smart" ? "Smart: a small neural network, good for most pictures and drawings. About a minute for a one megapixel picture." : "Best: the big network, the cleanest on photos. Several minutes for a one megapixel picture.") } }
                T { text: "Recent pictures"; font.pixelSize: 14; w: 600; color: Theme.i62 }
            }
            Flickable {
                SmoothWheel {}
                x: 20; y: leftCol.y + leftCol.implicitHeight + 10; width: parent.width - 40; height: Math.max(0, parent.height - y - 16)
                contentHeight: grid.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Flow {
                    id: grid
                    width: parent.width; spacing: 8
                    Repeater {
                        model: win.recent
                        Item {
                            required property string modelData
                            width: 78; height: 78
                            Rectangle { anchors.fill: parent; radius: 14; color: Theme.moonbg }
                            Image { anchors.fill: parent; anchors.margins: 0; source: "file://" + modelData; sourceSize: Qt.size(160, 160); fillMode: Image.PreserveAspectCrop; asynchronous: true
                                layer.enabled: true }
                            Rectangle { anchors.fill: parent; radius: 14; color: "transparent"; border.color: Theme.acc; border.width: pa.containsMouse ? 3 : 0 }
                            MouseArea { id: pa; anchors.fill: parent; hoverEnabled: true; onClicked: win.addPaths([modelData]) }
                        }
                    }
                }
                T { visible: win.recent.length === 0; text: "No pictures in Pictures, Downloads or Desktop yet."; font.pixelSize: 14; color: Theme.i55; width: parent.width; wrapMode: Text.WordWrap }
            }
        }

        // ---- right: preview and queue ----
        Item {
            width: parent.width - left.width; height: parent.height
            Item {
                id: prev
                x: 20; y: 20; width: parent.width - 40; height: Math.max(180, parent.height * 0.56)
                Rectangle { anchors.fill: parent; radius: 22; color: Theme.moonbg; clip: true
                    readonly property var j: win.sel >= 0 && win.sel < jobs.count ? jobs.get(win.sel) : null
                    Compare { id: cmpV; anchors.fill: parent; visible: parent.j !== null && parent.j.state === "done"
                        before: parent.j ? "file://" + parent.j.path : ""; after: parent.j && parent.j.state === "done" ? "file://" + parent.j.result : "" }
                    Image { anchors.fill: parent; anchors.margins: 8; visible: parent.j !== null && parent.j.state !== "done"; source: parent.j ? "file://" + parent.j.path : ""; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: 1400; smooth: false }
                    Rectangle { visible: parent.j !== null && parent.j.state === "run"; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                        width: 220; height: 36; radius: 18; color: "#B3000000"
                        T { anchors.centerIn: parent; text: "Working… " + (parent.parent.j ? parent.parent.j.progress : 0) + "%"; font.pixelSize: 14; color: "#FFFFFF"; w: 560 } }
                    T { visible: parent.j === null; anchors.centerIn: parent; width: parent.width - 60; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "Drop a picture here to start"; font.pixelSize: 20; color: Theme.i55 }
                }
            }
            Row {
                x: 20; y: prev.y + prev.height + 14; width: parent.width - 40; height: 34; spacing: 10
                T { anchors.verticalCenter: parent.verticalCenter; text: "Queue"; font.pixelSize: 18; w: 650; width: 80 }
                Item { width: parent.width - 80 - 130 - 100 - 30; height: 1 }
                Pill { visible: win.sel >= 0 && win.sel < jobs.count && jobs.get(win.sel).state === "done"; label: "Replay"; onClicked: cmpV.play() }
                Pill { visible: jobs.count > 0; label: "Clear finished"; onClicked: win.clearDone() }
            }
            ListView {
                SmoothWheel {}
                x: 20; y: prev.y + prev.height + 56; width: parent.width - 40; height: parent.height - y - 16
                clip: true; spacing: 6; boundsBehavior: Flickable.StopAtBounds
                model: jobs
                delegate: Item {
                    id: row
                    required property int index
                    required property string name
                    required property string path
                    required property int scale
                    required property string mode
                    required property string state
                    required property int progress
                    required property string result
                    required property int w
                    required property int h
                    required property string err
                    width: ListView.view.width; height: 64
                    Rectangle { anchors.fill: parent; radius: 16; color: win.sel === row.index ? Theme.moonbg : "transparent"; border.color: Theme.i12; border.width: win.sel === row.index ? 0 : 1 }
                    Image { x: 8; y: 8; width: 48; height: 48; source: "file://" + row.path; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectCrop; asynchronous: true }
                    T { x: 68; y: 8; width: parent.width - 68 - 230; elide: Text.ElideMiddle; text: row.name; font.pixelSize: 15; w: 560 }
                    T { x: 68; y: 32; width: parent.width - 68 - 230; elide: Text.ElideRight; font.pixelSize: 13; color: row.state === "error" ? Theme.errfg : Theme.i55
                        text: row.state === "wait" ? row.scale + "x, " + row.mode + ", waiting" : (row.state === "run" ? row.scale + "x, " + row.mode + ", " + row.progress + "%" : (row.state === "done" ? row.w + " x " + row.h + " pixels" : row.err)) }
                    Rectangle { visible: row.state === "run"; x: 68; y: 54; width: parent.width - 68 - 230; height: 4; radius: 2; color: Theme.i12
                        Rectangle { width: parent.width * row.progress / 100; height: parent.height; radius: 2; color: Theme.acc } }
                    Row { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        Pill { visible: row.state === "done"; label: "Open"; onClicked: win.sh(["/usr/local/bin/smof-fileops", "open", row.result]) }
                        Pill { visible: row.state === "done"; label: "In Files"; onClicked: win.sh(["/usr/local/bin/smof-files", row.result.substring(0, row.result.lastIndexOf("/"))]) }
                        Pill { label: row.state === "run" ? "Stop" : "Remove"; danger: row.state === "run"; onClicked: win.removeJob(row.index) }
                    }
                    MouseArea { anchors.fill: parent; z: -1; onClicked: win.sel = row.index }
                }
                T { visible: jobs.count === 0; text: "Nothing in the queue."; font.pixelSize: 15; color: Theme.i55 }
            }
        }
    }
}
