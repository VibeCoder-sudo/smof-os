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
    implicitHeight: body.implicitHeight + 32
    color: "transparent"
    visible: Ui.panelOpen

    // network state read from the system
    property string net: "…"
    Process {
        id: netp
        command: ["sh", "-c", "cat /sys/class/net/e*/operstate /sys/class/net/w*/operstate 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: pw.net = text.trim() === "up" ? "Connected" : "Off" }
    }
    Timer { interval: 4000; repeat: true; running: pw.visible; triggeredOnStart: true; onTriggered: netp.running = true }

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
                QTile { label: "Network"; sub: pw.net; on: pw.net === "Connected"; disabled: true }
                QTile { label: "Focus"; sub: Ui.dnd ? "No pop ups" : "Off"; on: Ui.dnd; onClicked: Ui.dnd = !Ui.dnd }
                QTile { label: "Appearance"; sub: Theme.dark ? "Dark" : "Light"; on: Theme.dark; onClicked: Theme.toggle() }
                QTile { label: "Calm"; sub: Ui.calm ? "Wallpaper still" : "Off"; on: Ui.calm; onClicked: Ui.calm = !Ui.calm }
                QTile { label: "Low power"; sub: Ui.lowpower ? "On" : "Off"; on: Ui.lowpower; onClicked: { Ui.lowpower = !Ui.lowpower; Ui.calm = Ui.lowpower } }
                QTile { label: "Settings"; sub: "Open"; onClicked: { Ui.closeAll(); Ui.openSettings() } }
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
                T { text: "Notifications"; w: 560; font.pixelSize: 17; color: Theme.acc; anchors.verticalCenter: parent.verticalCenter }
                Item {
                    visible: Notifs.count > 0
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: ct.implicitWidth + 24; height: 30
                    Rectangle { anchors.fill: parent; radius: 15; color: Theme.acc; opacity: cma.containsMouse ? .16 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
                    T { id: ct; anchors.centerIn: parent; text: "Clear all"; w: 560; font.pixelSize: 15; color: Theme.acc }
                    MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: Notifs.clearAll() }
                }
            }
            ListView {
                id: lv
                width: parent.width
                height: 185   // fixed: a popup that changes size while open redraws badly
                clip: true
                spacing: 8
                model: Notifs.store
                interactive: contentHeight > height
                // mouse wheel and touchpad scrolling, smooth
                NumberAnimation { id: wheelAnim; target: lv; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (ev) => {
                        // a mouse wheel sends whole notches (multiples of 120): flipped back to the classic direction.
                        // a touchpad sends small smooth steps: kept in the natural direction.
                        var ay = ev.angleDelta.y
                        var notch = ay !== 0 && Math.abs(ay) % 120 === 0
                        var d = notch ? -ay / 120 * 36 : (ev.pixelDelta.y !== 0 ? ev.pixelDelta.y * 0.5 : ay / 120 * 36)
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
                T { opacity: Notifs.count === 0 ? 1 : 0; Behavior on opacity { SequentialAnimation { PauseAnimation { duration: Notifs.count === 0 ? 350 : 0 } NumberAnimation { duration: 200 } } } anchors.centerIn: parent; text: Ui.dnd ? "Focus is on" : "No new notifications"; font.pixelSize: 16; color: Theme.i55 }
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
                        MouseArea { id: xma; anchors.fill: parent; hoverEnabled: true; onClicked: Notifs.remove(card.nid) }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.i12 }

            // power
            Row {
                spacing: 10
                PBtn { label: "Lock"; onClicked: { Ui.closeAll(); Quickshell.execDetached(["loginctl", "terminate-user", Quickshell.env("USER")]) } }
                PBtn { label: "Log out"; onClicked: { Ui.closeAll(); Quickshell.execDetached(["loginctl", "terminate-user", Quickshell.env("USER")]) } }
                PBtn { label: "Shut down"; danger: true; onClicked: { Ui.closeAll(); Quickshell.execDetached(["sudo", "-n", "/usr/bin/systemctl", "poweroff"]) } }
            }
        }
    }
}
