import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// panel under the clock: quick settings, brightness, notifications and the power buttons
PopupWindow {
    id: pw
    property var win
    property Item target
    anchor.window: win
    anchor.item: target
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    implicitWidth: 440
    // never taller than the screen below the bar, the content scrolls when it does not fit
    readonly property real maxH: (pw.win && pw.win.screen ? pw.win.screen.height : 768) - 80
    implicitHeight: Math.min(body.implicitHeight + 32, maxH)
    color: "transparent"
    visible: Ui.panelOpen

    // clipboard history, from cliphist
    property bool clipMode: false
    property var clips: []
    Process {
        id: clipP
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: {
            var out = [], L = text.split("\n")
            for (var i = 0; i < L.length && out.length < 40; i++) {
                var t = L[i].indexOf("\t"); if (t < 0) continue
                var id = L[i].substring(0, t), v = L[i].substring(t + 1)
                out.push({ id: id, text: v, image: /^\[\[ binary data/.test(v) })
            }
            pw.clips = out } }
    }
    function pasteClip(id) {
        Ui.closeAll()
        Quickshell.execDetached(["sh", "-c", "cliphist decode " + String(id).replace(/[^0-9]/g, "") + " | wl-copy; sleep 0.25; wtype -M ctrl -k v -m ctrl"])
    }
    onVisibleChanged: { if (!visible) clipMode = false; else nightGet.running = true }
    // network state read from the system
    property string net: "…"
    Process {
        id: netp
        command: ["sh", "-c", "cat /sys/class/net/e*/operstate /sys/class/net/w*/operstate 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: pw.net = text.trim() === "up" ? "Connected" : "Off" }
    }
    Timer { interval: 4000; repeat: true; running: pw.visible; triggeredOnStart: true; onTriggered: netp.running = true }

    // Night Light state, the tile turns it on and off through smof-night
    property bool nightOn: false
    Process { id: nightGet; command: ["sh", "-c", "/usr/local/bin/smof-night status | grep -q '\"on\": true' && echo on || echo off"]; stdout: StdioCollector { onStreamFinished: pw.nightOn = text.trim() === "on" } }
    Process { id: nightSet; property string v: "on"; command: ["/usr/local/bin/smof-night", "set", v]; onExited: nightGet.running = true }

    SystemClock { id: clk; precision: SystemClock.Minutes }

    component QTile: Item {
        id: qt
        property string label: ""
        property string sub: ""
        property bool on: false
        property bool disabled: false
        signal clicked()
        width: (440 - 32 - 20) / 3
        height: 92
        opacity: disabled ? .55 : 1
        Rectangle {
            anchors.fill: parent; radius: 24
            color: qt.on ? Theme.acc : Theme.glass2
            Behavior on color { ColorAnimation { duration: 200 } }
            scale: tma.pressed ? .97 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
        }
        Column {
            x: 14; y: 14; width: parent.width - 28
            spacing: 2
            T { text: qt.label; w: 560; font.pixelSize: 16; color: qt.on ? Theme.onacc : Theme.ink }
            T { text: qt.sub; font.pixelSize: 13; color: qt.on ? Theme.onacc : Theme.i55; opacity: .8; elide: Text.ElideRight; width: parent.width }
        }
        MouseArea { id: tma; anchors.fill: parent; enabled: !qt.disabled; onClicked: qt.clicked() }
    }
    component PBtn: Item {
        id: pb
        property string label: ""
        property bool danger: false
        signal clicked()
        width: (440 - 32 - 20) / 3
        height: 48
        Rectangle {
            anchors.fill: parent; radius: 24
            color: pb.danger ? Theme.sysbg : Theme.glass2
            Rectangle { anchors.fill: parent; radius: 24; color: Theme.acc; opacity: pma.containsMouse ? .14 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
        }
        T { anchors.centerIn: parent; text: pb.label; w: 560; font.pixelSize: 16; color: pb.danger ? (Theme.dark ? "#FFB59E" : "#B3401C") : Theme.ink }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: pb.clicked() }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 8
        radius: 30
        color: Theme.panelbg
        border.color: Theme.glassBorder
        Flickable {
            anchors.fill: parent; clip: true; boundsBehavior: Flickable.StopAtBounds
            contentWidth: width; contentHeight: body.implicitHeight + 32
            interactive: contentHeight > height
        Column {
            id: body
            x: 16; y: 16; width: parent.width - 32
            spacing: 12

            Item {
                width: parent.width; height: 30
                T { text: "Control"; w: 560; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                T { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDateTime(clk.date, "dddd, d MMMM"); font.pixelSize: 15; color: Theme.i55 }
            }

            Grid {
                columns: 3; spacing: 10
                QTile { label: "Wi-Fi"; sub: pw.net; on: pw.net === "Connected"; onClicked: { Ui.closeAll(); Ui.openSettings("network") } }
                QTile { label: "Focus"; sub: Ui.dnd ? "No pop ups" : "Off"; on: Ui.dnd; onClicked: Ui.dnd = !Ui.dnd }
                QTile { label: "Appearance"; sub: Theme.dark ? "Dark" : "Light"; on: Theme.dark; onClicked: Theme.toggle() }
                QTile { label: "Calm"; sub: Ui.calm ? "Wallpaper still" : "Off"; on: Ui.calm; onClicked: Ui.calm = !Ui.calm }
                QTile { label: "Low power"; sub: Ui.lowpower ? "On" : "Off"; on: Ui.lowpower; onClicked: { Ui.lowpower = !Ui.lowpower; Ui.calm = Ui.lowpower } }
                QTile { label: "Night Light"; sub: pw.nightOn ? "On" : "Off"; on: pw.nightOn; onClicked: { nightSet.v = pw.nightOn ? "off" : "on"; pw.nightOn = !pw.nightOn; nightSet.running = true } }
                QTile { label: "Bluetooth"; sub: "Open"; onClicked: { Ui.closeAll(); Ui.openSettings("bluetooth") } }
                QTile { label: "Settings"; sub: "Open"; onClicked: { Ui.closeAll(); Ui.openSettings() } }
                QTile { label: "Clipboard"; sub: pw.clipMode ? "Showing" : "History"; on: pw.clipMode; onClicked: { pw.clipMode = !pw.clipMode; if (pw.clipMode) clipP.running = true } }
                QTile { label: "Screenshot"; sub: "Select area"; onClicked: { Ui.closeAll(); Quickshell.execDetached(["sh", "-c", "sleep 0.4; /usr/local/bin/smof-shot area"]) } }
            }

            // brightness
            Rectangle {
                width: parent.width; height: 52; radius: 26; color: Theme.glass2
                Image { x: 18; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; sourceSize: Qt.size(66, 66); source: "file:///usr/share/smof/icons/sun" + Theme.sfx + ".svg" }
                Item {
                    id: sl
                    x: 56; width: parent.width - 80; height: parent.height
                    readonly property real p: (Ui.brightness - 0.3) / 0.7
                    Rectangle { id: trk; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 16; radius: 8; color: Theme.i12 }
                    Rectangle { id: fillr; anchors.verticalCenter: parent.verticalCenter; width: Math.max(0, sl.p * (parent.width - 8)) + 8; height: 16; radius: 8; color: Theme.acc }
                    Rectangle { x: fillr.width - 2; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 40; radius: 2; color: Theme.acc }
                    MouseArea {
                        anchors.fill: parent
                        function setFrom(mx) { Ui.brightness = 0.3 + 0.7 * Math.max(0, Math.min(1, (mx - 4) / (width - 8))) }
                        onPressed: (m) => setFrom(m.x)
                        onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
                    }
                }
            }

            // notifications
            Item {
                width: parent.width; height: 30
                T { text: pw.clipMode ? "Clipboard" : "Notifications"; w: 560; font.pixelSize: 17; color: Theme.acc; anchors.verticalCenter: parent.verticalCenter }
                Item {
                    visible: pw.clipMode && pw.clips.length > 0
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: cct.implicitWidth + 24; height: 30
                    Rectangle { anchors.fill: parent; radius: 15; color: Theme.acc; opacity: ccma.containsMouse ? .16 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
                    T { id: cct; anchors.centerIn: parent; text: "Clear"; w: 560; font.pixelSize: 15; color: Theme.acc }
                    MouseArea { id: ccma; anchors.fill: parent; hoverEnabled: true; onClicked: { Quickshell.execDetached(["cliphist", "wipe"]); pw.clips = [] } }
                }
                Item {
                    visible: !pw.clipMode && NotifStore.count > 0
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: ct.implicitWidth + 24; height: 30
                    Rectangle { anchors.fill: parent; radius: 15; color: Theme.acc; opacity: cma.containsMouse ? .16 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
                    T { id: ct; anchors.centerIn: parent; text: "Clear all"; w: 560; font.pixelSize: 15; color: Theme.acc }
                    MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: NotifStore.clearAll() }
                }
            }
            ListView {
                id: clv
                visible: pw.clipMode
                width: parent.width
                height: pw.clipMode ? 185 : 0
                clip: true
                spacing: 6
                model: pw.clips
                boundsBehavior: Flickable.StopAtBounds
                T { visible: pw.clips.length === 0; anchors.centerIn: parent; text: "Nothing copied yet"; font.pixelSize: 16; color: Theme.i55 }
                delegate: Rectangle {
                    required property var modelData
                    width: clv.width; height: 48; radius: 20; color: Theme.glass2
                    Rectangle { anchors.fill: parent; radius: 20; color: Theme.acc; opacity: cpm.containsMouse ? .14 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
                    T { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 32; elide: Text.ElideRight; maximumLineCount: 1
                        text: modelData.image ? "Picture" : modelData.text.replace(/\s+/g, " "); font.pixelSize: 15; color: modelData.image ? Theme.acc : Theme.ink }
                    MouseArea { id: cpm; anchors.fill: parent; hoverEnabled: true; onClicked: pw.pasteClip(modelData.id) }
                }
            }
            ListView {
                id: lv
                visible: !pw.clipMode
                width: parent.width
                height: 185   // fixed: a popup that changes size while open redraws badly
                clip: true
                spacing: 8
                model: NotifStore.store
                interactive: contentHeight > height
                // mouse wheel and touchpad scrolling, smooth
                NumberAnimation { id: wheelAnim; target: lv; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (ev) => {
                        // the direction is set in Settings, Display, Scrolling: here wheel up always shows earlier cards
                        var ay = ev.angleDelta.y
                        var d = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y * 0.5 : ay / 120 * 36
                        var max = Math.max(0, lv.contentHeight - lv.height)
                        var from = wheelAnim.running ? wheelAnim.to : lv.contentY
                        var to = Math.max(0, Math.min(max, from - d))
                        wheelAnim.stop()
                        wheelAnim.from = lv.contentY
                        wheelAnim.to = to
                        wheelAnim.start()
                    }
                }
                add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260 } }
                remove: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; to: 0; duration: 200 } NumberAnimation { property: "x"; to: 80; duration: 200; easing.type: Easing.InCubic } } }
                displaced: Transition { NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic } NumberAnimation { property: "opacity"; to: 1; duration: 0 } }
                T { opacity: NotifStore.count === 0 ? 1 : 0; Behavior on opacity { SequentialAnimation { PauseAnimation { duration: NotifStore.count === 0 ? 350 : 0 } NumberAnimation { duration: 200 } } } anchors.centerIn: parent; text: Ui.dnd ? "Focus is on" : "No new notifications"; font.pixelSize: 16; color: Theme.i55 }
                delegate: Rectangle {
                    id: card
                    required property real nid
                    required property string app
                    required property string summary
                    required property string body
                    required property string level
                    required property real time
                    width: lv.width
                    height: Math.max(68, tx.implicitHeight + 24)
                    radius: 24
                    color: Theme.glass2
                    border.color: level === "info" ? "transparent" : Theme.lvFg(level)
                    border.width: level === "info" ? 0 : 2
                    Rectangle {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 44; radius: 22
                        color: Theme.lvBg(card.level)
                        T { anchors.centerIn: parent; text: card.level === "info" ? (card.app || "?").charAt(0).toUpperCase() : "!"; w: 700; font.pixelSize: card.level === "info" ? 20 : 24; color: Theme.lvFg(card.level) }
                    }
                    Column {
                        id: tx
                        x: 68; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 68 - 64
                        spacing: 1
                        T { text: card.summary; w: 560; font.pixelSize: 17; elide: Text.ElideRight; width: parent.width }
                        T { visible: text !== ""; text: card.body; font.pixelSize: 15; color: Theme.i62; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; width: parent.width }
                    }
                    T {
                        anchors.right: parent.right; anchors.rightMargin: 16; y: 14
                        text: Qt.formatDateTime(new Date(card.time), "HH:mm")
                        font.pixelSize: 13; color: Theme.i5
                    }
                    Item {
                        id: xb
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        width: 28; height: 28
                        Rectangle { anchors.fill: parent; radius: 14; color: Theme.ink; opacity: xma.containsMouse ? .12 : 0 }
                        T { anchors.centerIn: parent; text: "×"; font.pixelSize: 22; color: Theme.i55 }
                        MouseArea { id: xma; anchors.fill: parent; hoverEnabled: true; onClicked: NotifStore.remove(card.nid) }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.i12 }

            // power
            Row {
                spacing: 10
                PBtn { label: "Log out"; onClicked: { Ui.closeAll(); Quickshell.execDetached(["loginctl", "terminate-user", Quickshell.env("USER")]) } }
                PBtn { label: "Restart"; onClicked: { Ui.closeAll(); Quickshell.execDetached(["sudo", "-n", "/usr/bin/systemctl", "reboot"]) } }
                PBtn { label: "Shut down"; danger: true; onClicked: { Ui.closeAll(); Quickshell.execDetached(["sudo", "-n", "/usr/bin/systemctl", "poweroff"]) } }
            }
        }
        }
    }
}
