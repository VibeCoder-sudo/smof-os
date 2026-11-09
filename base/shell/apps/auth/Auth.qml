import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick

PanelWindow {
    id: w
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "smof-auth"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    visible: shown || veil.opacity > 0.01

    // ---- what is being asked ----
    // sudo requests come from the askpass helper over IPC, polkit requests from the polkit agent
    property var sudoQueue: []                 // [{fifo, cmd, retry, user}]
    property var cur: null                     // the sudo request on screen
    property bool checking: false              // a sudo password was sent, waiting to see if sudo asks again
    property string errorText: ""
    readonly property bool polkitOn: agent.isActive && agent.flow !== null
    readonly property bool sudoOn: cur !== null
    readonly property bool shown: polkitOn || sudoOn
    readonly property string user: sudoOn ? (cur.user || Quickshell.env("USER")) : Quickshell.env("USER")

    readonly property string title: sudoOn ? "Allow this app to make changes?" : "Permission needed"
    readonly property string lead: sudoOn
        ? "A program is asking for administrator rights."
        : (polkitOn ? (agent.flow.message || "An app wants to make changes to your system.") : "")
    readonly property string detail: sudoOn ? cur.cmd : (polkitOn ? agent.flow.actionId : "")

    function addSudo(fifo, cmd, retry, user) {
        if (cur && cur.fifo === fifo) return
        var item = { fifo: fifo, cmd: cmd, retry: retry, user: user }
        if (cur === null || checking) { startSudo(item); return }
        sudoQueue = sudoQueue.concat([item])
    }
    function startSudo(item) {
        cur = item; checking = false; checkT.stop()
        errorText = item.retry ? "That password is not right. Try again." : ""
        pw.text = ""; pw.forceActiveFocus()
        shake.stop()
        if (item.retry) shake.start()
    }
    function nextSudo() {
        cur = null; checking = false
        if (sudoQueue.length > 0) { var n = sudoQueue[0]; sudoQueue = sudoQueue.slice(1); startSudo(n) }
    }
    function dropSudo(fifo) {
        sudoQueue = sudoQueue.filter(function (q) { return q.fifo !== fifo })
        if (cur && cur.fifo === fifo) nextSudo()
    }
    function reply(text) {
        replyP.command = ["sh", "-c", "cat > \"$0\"", cur.fifo]
        replyP.running = true
        replyP.pending = text + "\n"
    }
    Process {
        id: replyP
        property string pending: ""
        stdinEnabled: true
        onStarted: { write(pending); pending = ""; stdinEnabled = false }
        onExited: stdinEnabled = true
    }
    Timer { id: checkT; interval: 4500; onTriggered: if (w.checking) w.nextSudo() }

    function submit() {
        var t = pw.text
        if (t === "") return
        if (sudoOn) {
            reply(t); checking = true; errorText = ""; checkT.restart()
        } else if (polkitOn) {
            errorText = ""; agent.flow.submit(t)
        }
        pw.text = ""
    }
    function cancel() {
        if (sudoOn) { reply("__SMOF_CANCEL__"); nextSudo() }
        else if (polkitOn) agent.flow.cancelAuthenticationRequest()
    }

    PolkitAgent { id: agent }
    Connections {
        target: agent.flow
        function onFailed() { w.errorText = "That password is not right. Try again."; pw.text = ""; shake.restart() }
    }
    onPolkitOnChanged: if (polkitOn) { errorText = ""; pw.text = ""; pw.forceActiveFocus() }
    onShownChanged: if (shown) { pw.forceActiveFocus() }

    // ---- look ----
    Rectangle { id: veil; anchors.fill: parent; color: "#000000"; opacity: w.shown ? .52 : 0; Behavior on opacity { NumberAnimation { duration: 330; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } } }
    MouseArea { anchors.fill: parent; enabled: w.shown }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 470; height: col.implicitHeight + 44
        radius: 34
        color: Theme.menubg
        border.color: Theme.glassBorder
        opacity: w.shown ? 1 : 0
        scale: w.shown ? 1 : .94
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } }
        Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        transform: Translate { id: tr; x: 0 }
        SequentialAnimation { id: shake
            NumberAnimation { target: tr; property: "x"; to: -14; duration: 60 }
            NumberAnimation { target: tr; property: "x"; to: 12; duration: 70 }
            NumberAnimation { target: tr; property: "x"; to: -8; duration: 60 }
            NumberAnimation { target: tr; property: "x"; to: 0; duration: 60 } }

        Column {
            id: col
            x: 28; y: 26; width: parent.width - 56; spacing: 16
            Row {
                spacing: 16
                Rectangle { width: 56; height: 56; radius: 28; color: Theme.sysbg
                    Image { anchors.centerIn: parent; width: 28; height: 28; sourceSize: Qt.size(84, 84); source: "file:///usr/share/smof/icons/shield" + Theme.sfx + ".svg" } }
                Column { anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    T { text: w.title; w: 640; font.pixelSize: 22; width: col.width - 72; wrapMode: Text.Wrap }
                    T { text: w.lead; font.pixelSize: 15; color: Theme.i62; width: col.width - 72; wrapMode: Text.Wrap } }
            }
            // what exactly
            Rectangle {
                visible: w.detail !== ""
                width: parent.width; height: dt.implicitHeight + 22; radius: 16; color: Theme.glass2
                T { id: dt; x: 14; y: 11; width: parent.width - 28; text: w.detail; font.pixelSize: 14; color: Theme.ink; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight; font.family: "monospace" }
            }
            T { text: "Enter the password for " + w.user + " to allow it."; font.pixelSize: 15; color: Theme.i62; width: parent.width; wrapMode: Text.Wrap }
            // password
            Rectangle {
                width: parent.width; height: 52; radius: 26; color: Theme.glass2
                border.color: w.errorText !== "" ? Theme.errfg : "transparent"; border.width: 2
                T { visible: pw.text === "" && !w.checking; x: 22; anchors.verticalCenter: parent.verticalCenter; text: "Password"; font.pixelSize: 18; color: Theme.i5 }
                TextInput { id: pw; x: 22; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter; echoMode: TextInput.Password; passwordCharacter: "\u25CF"
                    font.family: "Google Sans Flex"; font.pixelSize: 18; color: Theme.ink; clip: true; enabled: !w.checking
                    Keys.onReturnPressed: w.submit(); Keys.onEscapePressed: w.cancel() }
                Row { visible: w.checking; anchors.centerIn: parent; spacing: 10
                    Spinner { width: 22; height: 22 }
                    T { text: "Checking..."; font.pixelSize: 16; color: Theme.i62; anchors.verticalCenter: parent.verticalCenter } }
            }
            T { visible: w.errorText !== ""; text: w.errorText; font.pixelSize: 14; color: Theme.errfg; width: parent.width }
            Row {
                spacing: 10; anchors.right: parent.right
                Item { width: cT.implicitWidth + 40; height: 44
                    Rectangle { anchors.fill: parent; radius: 22; color: Theme.moonbg; Rectangle { anchors.fill: parent; radius: 22; color: Theme.acc; opacity: cma.pressed ? .22 : (cma.containsMouse ? .12 : 0) } }
                    T { id: cT; anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 16; w: 560; color: Theme.acc }
                    MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: w.cancel() } }
                Item { width: aT.implicitWidth + 40; height: 44; opacity: pw.text !== "" && !w.checking ? 1 : .5
                    Rectangle { anchors.fill: parent; radius: 22; color: Theme.acc; Rectangle { anchors.fill: parent; radius: 22; color: "#000000"; opacity: ama.pressed ? .18 : 0 } }
                    T { id: aT; anchors.centerIn: parent; text: "Allow"; font.pixelSize: 16; w: 600; color: Theme.onacc }
                    MouseArea { id: ama; anchors.fill: parent; enabled: pw.text !== "" && !w.checking; onClicked: w.submit() } }
            }
        }
    }
}
