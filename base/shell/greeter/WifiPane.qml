import Quickshell
import Quickshell.Io
import QtQuick

// Wi-Fi for the first screens (live image and first run): list the networks, pick one, type the password. Uses smof-wifi.
Column {
    id: wp
    signal back()
    property var nets: []
    property string state: ""          // text under the title
    property string asking: ""         // network that waits for a password
    property string busy: ""
    property bool radio: true
    spacing: 12

    function rescan() { if (!scanP.running) scanP.running = true }
    Component.onCompleted: rescan()
    Timer { interval: 7000; repeat: true; running: wp.visible; onTriggered: wp.rescan() }
    Process {
        id: scanP
        command: ["/usr/local/bin/smof-wifi", "scan"]
        stdout: StdioCollector { onStreamFinished: { try { var o = JSON.parse(text); wp.radio = o.radio; wp.nets = o.nets || []
            wp.state = !o.ok ? (o.error || "No Wi-Fi") : (!o.radio ? "Wi-Fi is off" : (wp.nets.length === 0 ? "Looking for networks…" : "Choose a network")) } catch (e) {} } }
    }
    Process {
        id: joinP
        property string ssid: ""
        property string pw: ""
        command: ["/usr/local/bin/smof-wifi", "connect", ssid]
        stdinEnabled: true
        onStarted: { write(pw + "\n"); stdinEnabled = false }
        stdout: StdioCollector { onStreamFinished: { wp.busy = ""; try { var o = JSON.parse(text); if (o.ok) { wp.asking = ""; wp.state = "Connected" } else wp.state = o.error || "Could not connect" } catch (e) {} wp.rescan() } }
    }
    Process { id: radioP; command: ["/usr/local/bin/smof-wifi", "radio", "on"]; onExited: wp.rescan() }
    function join(ssid, pw) { wp.busy = ssid; wp.state = "Connecting to " + ssid + "…"; joinP.ssid = ssid; joinP.pw = pw || ""; joinP.stdinEnabled = true; joinP.running = true }

    T { text: "Wi-Fi"; font.pixelSize: 40; w: 600; color: "#FFFFFF" }
    T { text: wp.state; font.pixelSize: 16; color: "#B8FFFFFF" }
    Rectangle { visible: !wp.radio; width: 220; height: 52; radius: 26; color: Theme.acc
        T { anchors.centerIn: parent; text: "Turn Wi-Fi on"; font.pixelSize: 18; w: 620; color: Theme.onacc }
        MouseArea { anchors.fill: parent; onClicked: radioP.running = true } }
    Flickable {
        width: parent.width; height: Math.min(330, list.implicitHeight); contentHeight: list.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: list; width: parent.width; spacing: 8
            Repeater {
                model: wp.nets
                Column {
                    id: it
                    required property var modelData
                    width: list.width; spacing: 6
                    Rectangle {
                        width: parent.width; height: 62; radius: 20; color: modelData.active ? "#33FFFFFF" : "#1AFFFFFF"; border.color: modelData.active ? Theme.acc : "#22FFFFFF"
                        T { x: 20; y: 10; text: modelData.ssid; font.pixelSize: 18; w: 600; color: "#FFFFFF"; width: parent.width - 180; elide: Text.ElideRight }
                        T { x: 20; y: 36; text: (modelData.active ? "Connected, " : (modelData.known ? "Saved, " : "")) + (modelData.secure ? "Secured" : "Open") + ", " + modelData.signal + "%"; font.pixelSize: 13; color: "#B8FFFFFF" }
                        T { anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter; visible: !modelData.active
                            text: wp.busy === modelData.ssid ? "Connecting" : "Connect"; font.pixelSize: 16; w: 600; color: Theme.acc }
                        MouseArea { anchors.fill: parent; enabled: !modelData.active
                            onClicked: { if (modelData.secure && !modelData.known) { wp.asking = modelData.ssid; pin.text = ""; pin.forceActiveFocus() } else wp.join(modelData.ssid) } }
                    }
                    Rectangle {
                        visible: wp.asking === modelData.ssid
                        width: parent.width; height: 54; radius: 27; color: "#26FFFFFF"
                        TextInput { id: pin; anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 120; verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password; font.family: "Google Sans Flex"; font.pixelSize: 18; color: "#FFFFFF"; clip: true
                            onAccepted: if (text.length >= 8) wp.join(modelData.ssid, text) }
                        T { visible: pin.text === ""; x: 22; anchors.verticalCenter: parent.verticalCenter; text: "Password"; font.pixelSize: 18; color: "#80FFFFFF" }
                        Rectangle { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 100; height: 42; radius: 21; color: Theme.acc
                            T { anchors.centerIn: parent; text: "Join"; font.pixelSize: 17; w: 620; color: Theme.onacc }
                            MouseArea { anchors.fill: parent; onClicked: if (pin.text.length >= 8) wp.join(modelData.ssid, pin.text) } }
                    }
                }
            }
        }
    }
    Rectangle { width: 170; height: 58; radius: 29; color: "#26FFFFFF"; T { anchors.centerIn: parent; text: "Done"; font.pixelSize: 19; w: 560; color: "#FFFFFF" }
        MouseArea { anchors.fill: parent; onClicked: wp.back() } }
}
