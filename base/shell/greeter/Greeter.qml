import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Effects

// Smof lock screen and login, a QML port of lockscreen.html
Item {
    id: root
    property string phase: "pre"          // pre, lock, pin, auth, launch, oobe
    property var userInfo: ({ name: "MJ", user: "mj", avatar: "mj.jpg" })
    property string oobeState: ""          // pending or preview on a fresh system, empty once set up
    readonly property bool oobe: phase === "oobe"
    property string pin: ""
    property string sub: "Type your 4 digit PIN"
    property int step: 0
    readonly property bool inLock: phase === "pre" || phase === "lock"
    readonly property bool login: !inLock
    readonly property real fit: Math.min(width / 1440, height / 1024)
    readonly property real cover: Math.max(width / 1440, height / 1024)
    focus: true

    SystemClock { id: clock; precision: SystemClock.Minutes }

    FileView { id: uinfo; path: "/var/lib/smof/user.json"; blockLoading: true; watchChanges: true; printErrors: false; onFileChanged: reload()
        onLoaded: { try { root.userInfo = JSON.parse(text()) } catch (e) {} } }
    FileView { id: ostate; path: "/var/lib/smof/oobe-state"; blockLoading: true; watchChanges: true; printErrors: false; onFileChanged: reload()
        onLoaded: root.oobeState = text().trim() }

    Component.onCompleted: {
        try { root.userInfo = JSON.parse(uinfo.text()) } catch (e) {}
        try { root.oobeState = ostate.text().trim() } catch (e) {}
        Backdrop.item = blurSrc
        if (oobeState === "pending" || oobeState === "preview") { phase = "oobe"; oobeUi.forceActiveFocus() }
        else { forceActiveFocus(); phase = "lock"; intro.start() }
    }

    Process {
        id: oobeProc
        property string payload: ""
        stdinEnabled: true
        command: ["sudo", "-n", "/usr/local/sbin/smof-oobe"]
        onStarted: write(payload)
        // what sudo or the helper printed, shown on screen when the setup fails so the cause is visible without any console
        stderr: StdioCollector { id: oobeErr }
        stdout: StdioCollector { id: oobeOut }
        onExited: (code) => {
            oobeUi.busy = false
            if (code === 0) oobeUi.ok = true
            else {
                var t = (oobeErr.text + " " + oobeOut.text).trim().split("\n").slice(-2).join(" ")
                oobeUi.errText = "code " + code + (t !== "" ? ", " + t : "")
                oobeLog.reload(); oobeUi.goto(4); oobeUi.hint = ""
            }
        }
    }
    // the helper keeps its own log, the last lines are added to the message
    FileView { id: oobeLog; path: "/var/lib/smof/oobe.log"; printErrors: false
        onLoaded: { var l = text().trim().split("\n"); if (oobeUi.errText !== "") oobeUi.errText += " | " + l.slice(-2).join(" ") } }
    Timer { id: previewT; interval: 2500; onTriggered: oobeUi.ok = true }
    function runSetup(name, user, pin, dark, layouts) {
        if (oobeState === "preview") { previewT.start(); return }
        oobeProc.payload = name + "\n" + user + "\n" + pin + "\n" + (dark ? "dark" : "light") + "\n" + layouts + "\n"
        oobeProc.running = true
    }
    function afterSetup() {
        if (oobeState === "preview") { Theme.setDark(oobeUi.origDark, false); oobeUi.step = 0; Quickshell.execDetached(["rm", "-f", "/var/lib/smof/oobe-state"]) }
        oobeState = ""; step = 0; pin = ""; phase = "lock"; forceActiveFocus(); intro.restart()
    }
    Timer { id: intro; interval: 90; repeat: true; onTriggered: { if (root.step < 12) root.step++; else stop() } }

    function submit() {
        phase = "auth"; sub = "Signing in..."
        if (Greetd.available) Greetd.createSession(root.userInfo.user)
        else devAuth.start()
    }
    function fail() { pin = ""; phase = "pin"; sub = "Wrong PIN, try again"; shake.start() }
    function ok() {
        sub = "Signing in..."; phase = "launch"
        if (Greetd.available) launchT.start()
        else resetT.start()
    }
    Timer { id: devAuth; interval: 700; onTriggered: root.pin === "1234" ? root.ok() : root.fail() }
    Timer { id: launchT; interval: 800; onTriggered: Greetd.launch(["/usr/local/bin/smof-session"]) }
    Timer { id: resetT; interval: 2500; onTriggered: { root.pin = ""; root.sub = "Type your 4 digit PIN"; root.step = 0; root.phase = "lock"; intro.restart() } }
    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) { if (responseRequired) Greetd.respond(root.pin) }
        function onAuthFailure(message) { root.fail() }
        function onReadyToLaunch() { root.ok() }
    }

    Keys.onPressed: (e) => {
        if (phase === "oobe") return
        if (phase === "lock") { phase = "pin"; return }
        if (phase === "pin") {
            if (e.key === Qt.Key_Backspace) pin = pin.slice(0, -1)
            else if (/^[0-9]$/.test(e.text)) { pin += e.text; if (pin.length >= 4) submit() }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: if (root.phase === "lock") root.phase = "pin" }

    Rectangle { anchors.fill: parent; color: "#0f0d16" }

    // blurred copy of the wallpaper, glass cards sample from it
    Item {
        width: 1440; height: 1024; anchors.centerIn: parent; scale: root.cover
        MultiEffect { id: blurSrc; anchors.fill: parent; source: wpTex; blurEnabled: true; blur: 0.5; blurMax: 24 }
    }
    Component.onDestruction: Backdrop.item = null

    // wallpaper, scaled to cover the window
    Item {
        id: wpBox
        width: 1440; height: 1024; anchors.centerIn: parent; scale: root.cover
        Wallpaper { x: -62; y: -60; scope: "lock"; depth: root.inLock ? 0 : 1 }
    }
    ShaderEffectSource { id: wpTex; sourceItem: wpBox; width: 720; height: 512; textureSize: Qt.size(720, 512); live: true; visible: false; smooth: true }

    // the 1440 x 1024 design frame, scaled to fit
    Item {
        id: stage
        width: 1440; height: 1024; anchors.centerIn: parent; scale: root.fit

        // clock
        Item {
            id: clk
            width: Math.max(tm.implicitWidth, Look.lockDate ? dt.implicitWidth : 0); height: Look.lockDate ? 139 : 120
            transformOrigin: Item.Top
            x: (root.login || Look.lockCenter) ? 720 - width / 2 : 100
            y: root.login ? 70 : 100
            scale: (root.login ? .62 : 1) * Look.lockClock
            opacity: (root.step >= 1 && !root.oobe) ? 1 : 0
            property real drop: root.step >= 1 ? 0 : -24
            transform: Translate { y: clk.drop }
            Behavior on drop { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 500 } }
            Behavior on x { SequentialAnimation { PauseAnimation { duration: root.login ? 350 : 0 } NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
            Behavior on y { SequentialAnimation { PauseAnimation { duration: root.login ? 350 : 0 } NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
            Behavior on scale { SequentialAnimation { PauseAnimation { duration: root.login ? 350 : 0 } NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
            T { id: tm; y: 0; width: clk.width; horizontalAlignment: Look.lockCenter ? Text.AlignHCenter : Text.AlignLeft; height: 120; verticalAlignment: Text.AlignVCenter; text: Qt.formatDateTime(clock.date, "HH:mm"); w: 385; font.pixelSize: 96; color: "#FFFFFF" }
            T { id: dt; visible: Look.lockDate; y: 106; width: clk.width; horizontalAlignment: Look.lockCenter ? Text.AlignHCenter : Text.AlignLeft; text: Qt.formatDateTime(clock.date, "dddd, MMMM d"); w: 470; font.pixelSize: 26; color: "#F2FFFFFF" }
        }

        // first run setup
        Oobe {
            id: oobeUi
            anchors.fill: parent
            visible: root.oobe
            persist: root.oobeState !== "preview"
            onSetup: (name, user, pin, dark, layouts) => root.runSetup(name, user, pin, dark, layouts)
            onFinished: root.afterSetup()
        }

        // hint
        T {
            id: hint
            x: 0; width: 1440; y: 984; horizontalAlignment: Text.AlignHCenter
            text: "Press any button to login"; font.pixelSize: 24; color: "#FFFFFF"
            opacity: root.inLock && root.step >= 9 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
            SequentialAnimation on scale { running: false }
        }

        // pin entry
        Item {
            id: pinbox
            x: 570; y: 430; width: 300; height: 300
            opacity: (root.login && !root.oobe) ? 1 : 0
            property real rise: root.login ? 0 : 30
            transform: Translate { y: pinbox.rise }
            Behavior on opacity { SequentialAnimation { PauseAnimation { duration: root.login ? 950 : 0 } NumberAnimation { duration: 600 } } }
            Behavior on rise { SequentialAnimation { PauseAnimation { duration: root.login ? 950 : 0 } NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
            Loader {
                x: 86; width: 128; height: 128
                sourceComponent: root.userInfo.avatar ? photoAv : letterAv
            }
            Component { id: photoAv; CircleImage { width: 128; height: 128; source: "file:///usr/share/smof/" + root.userInfo.avatar } }
            Component {
                id: letterAv
                Rectangle {
                    width: 128; height: 128; radius: 64
                    gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#F6B8D4" } GradientStop { position: 1; color: "#8E7BDB" } }
                    T { anchors.centerIn: parent; text: (root.userInfo.name || "?").charAt(0).toUpperCase(); font.pixelSize: 64; w: 560; color: "#FFFFFF" }
                }
            }
            T { y: 154; width: 300; horizontalAlignment: Text.AlignHCenter; text: root.userInfo.name; w: 560; font.pixelSize: 30; color: "#FFFFFF" }
            Spinner {
                x: (parent.width - width) / 2; y: 227 - height / 2; width: 52; height: 52
                opacity: root.phase === "auth" || root.phase === "launch" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250 } }
            }
            Row {
                id: dots
                opacity: root.phase === "auth" || root.phase === "launch" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
                x: 87; y: 218; spacing: 18
                Repeater {
                    model: 4
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: root.pin.length > index ? "#FFFFFF" : "transparent"
                        border.color: "#E6FFFFFF"; border.width: 2
                        scale: root.pin.length > index ? 1.15 : 1
                        Behavior on scale { NumberAnimation { duration: 200 } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }
            T { y: 262; width: 300; horizontalAlignment: Text.AlignHCenter; text: root.sub; font.pixelSize: 18; color: "#CCFFFFFF" }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: dots; property: "x"; to: 77; duration: 90 }
                NumberAnimation { target: dots; property: "x"; to: 97; duration: 90 }
                NumberAnimation { target: dots; property: "x"; to: 87; duration: 90 }
            }
        }
    }

    // pulse for the hint
    SequentialAnimation {
        running: root.inLock && root.step >= 9; loops: Animation.Infinite
        NumberAnimation { target: hint; property: "opacity"; to: .55; duration: 1300 }
        NumberAnimation { target: hint; property: "opacity"; to: 1; duration: 1300 }
    }


    // launch fade: the lock screen goes to the same dark colour the session starts with, then the desktop fades in
    Rectangle { anchors.fill: parent; color: "#0F0D16"; opacity: root.phase === "launch" ? 1 : 0; visible: opacity > 0.001
        Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.InOutQuad } } }
}
