import Quickshell
import QtQuick

// First run setup: hello, name, PIN, look, keyboard, finish. Lives in the 1440 x 1024 stage of the greeter.
FocusScope {
    id: o
    property bool persist: true            // false in preview: nothing is written
    property bool busy: false              // the root helper is working
    property bool ok: false                // helper finished fine
    signal setup(string name, string user, string pin, bool dark, string layouts)
    signal finished()

    property int step: 0                   // 0 hello, 1 name, 2 pin, 3 look, 4 keyboard, 5 working, 6 done
    property string nameText: ""
    property string pin1: ""
    property string pin2: ""
    property bool confirming: false
    property string hint: ""
    property bool origDark: Theme.dark
    readonly property string pinNow: confirming ? pin2 : pin1
    readonly property string userName: {
        var u = nameText.toLowerCase().replace(/[^a-z0-9]/g, "")
        if (u.length === 0 || !/^[a-z]/.test(u)) u = "user" + u
        return u.substring(0, 24)
    }

    function goto(n) { hint = ""; step = n; if (n === 1) nameField.forceActiveFocus(); else { nameField.focus = false; o.forceActiveFocus() } }
    function digit(d) {
        if (step !== 2) return
        if (!confirming) { if (pin1.length < 4) pin1 += d; if (pin1.length === 4) confirmT.start() }
        else { if (pin2.length < 4) pin2 += d; if (pin2.length === 4) checkT.start() }
    }
    function back() { if (step !== 2) return; if (confirming) pin2 = pin2.slice(0, -1); else pin1 = pin1.slice(0, -1) }
    Timer { id: confirmT; interval: 350; onTriggered: { o.confirming = true; o.hint = "" } }
    Timer { id: checkT; interval: 350
        onTriggered: {
            if (o.pin1 === o.pin2) o.goto(3)
            else { o.hint = "The PINs do not match, try again"; o.pin1 = ""; o.pin2 = ""; o.confirming = false; shake.start() }
        }
    }
    function finish() {
        var ls = kb.picked.map(function (x) { return x.l }).join(",")
        var vs = kb.picked.map(function (x) { return x.v }).join(",")
        goto(5); busy = true; setup(nameText.trim(), userName, pin1, Theme.dark, ls + "|" + vs + "|" + kb.toggle)
    }
    onOkChanged: if (ok && step === 5) { busy = false; goto(6); doneT.start() }
    Timer { id: doneT; interval: 2200; onTriggered: o.finished() }

    Keys.onPressed: (e) => {
        if (step === 0 && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)) goto(1)
        else if (step === 2) { if (e.key === Qt.Key_Backspace) back(); else if (/^[0-9]$/.test(e.text)) digit(e.text) }
        else if (step === 3 && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) goto(4)
        else if (step === 3 && e.key === Qt.Key_Left) Theme.setDark(false, persist)
        else if (step === 3 && e.key === Qt.Key_Right) Theme.setDark(true, persist)
    }

    // greeting words change every couple of seconds
    readonly property var hellos: ["Hello", "Привет", "Hola", "Bonjour", "こんにちは", "Hallo", "Ciao", "你好"]
    property int hi: 0
    Timer { interval: 2200; repeat: true; running: o.step === 0; onTriggered: o.hi = (o.hi + 1) % o.hellos.length }

    component Pill: Item {
        id: pl
        property string label: ""
        property bool filled: true
        property bool enabled2: true
        signal clicked()
        width: pt.implicitWidth + 64; height: 56
        opacity: enabled2 ? 1 : .45
        Rectangle { anchors.fill: parent; radius: 28; color: pl.filled ? Theme.acc : Theme.glass2; border.color: pl.filled ? "transparent" : Theme.glassBorder
            Rectangle { anchors.fill: parent; radius: 28; color: pl.filled ? Theme.onacc : Theme.acc; opacity: pma.containsMouse ? .12 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
            scale: pma.pressed ? .97 : 1; Behavior on scale { NumberAnimation { duration: 100 } } }
        T { id: pt; anchors.centerIn: parent; text: pl.label; w: 560; font.pixelSize: 20; color: pl.filled ? Theme.onacc : Theme.ink }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; enabled: pl.enabled2; onClicked: pl.clicked() }
    }

    // the card
    Item {
        id: card
        x: 340; y: 225; width: 760; height: 590
        Glass { anchors.fill: parent; radius: 40 }

        // progress dots
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 28; spacing: 10
            visible: o.step > 0 && o.step < 5
            Repeater { model: 4
                Rectangle { width: index + 1 === o.step ? 28 : 10; height: 10; radius: 5; color: index + 1 <= o.step ? Theme.acc : Theme.i12
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } } } }
        }

        // 0 hello
        Item {
            anchors.fill: parent; visible: opacity > 0; opacity: o.step === 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            T { id: hw; anchors.horizontalCenter: parent.horizontalCenter; y: 110; text: o.hellos[o.hi]; font.pixelSize: 110; w: 420
                SequentialAnimation on opacity { running: o.step === 0; loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 1; duration: 500 } PauseAnimation { duration: 1300 } NumberAnimation { from: 1; to: 0; duration: 400 } } }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 290; text: "Welcome to Donut Smof"; font.pixelSize: 26; w: 470; color: Theme.i62 }
            Pill { anchors.horizontalCenter: parent.horizontalCenter; y: 400; label: "Get started"; onClicked: o.goto(1) }
        }

        // 1 name
        Item {
            anchors.fill: parent; visible: opacity > 0; opacity: o.step === 1 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 100; text: "What should we call you?"; font.pixelSize: 38; w: 560 }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 156; text: "This name is shown on the lock screen"; font.pixelSize: 20; color: Theme.i62 }
            Rectangle {
                x: 130; y: 230; width: 500; height: 64; radius: 32; color: Theme.glass2
                border.width: nameField.activeFocus ? 2 : 1; border.color: nameField.activeFocus ? Theme.acc : Theme.glassBorder
                TextInput {
                    id: nameField
                    anchors.fill: parent; anchors.leftMargin: 26; anchors.rightMargin: 26
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: "Google Sans Flex"; font.pixelSize: 24; color: Theme.ink
                    maximumLength: 30; clip: true
                    selectionColor: Theme.acc
                    onTextChanged: o.nameText = text
                    onAccepted: if (o.nameText.trim().length > 0) o.goto(2)
                    T { visible: nameField.text.length === 0; text: "Your name"; font.pixelSize: 24; color: Theme.i5; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Pill { anchors.horizontalCenter: parent.horizontalCenter; y: 400; label: "Continue"; enabled2: o.nameText.trim().length > 0; onClicked: o.goto(2) }
        }

        // 2 pin
        Item {
            anchors.fill: parent; visible: opacity > 0; opacity: o.step === 2 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 100; text: o.confirming ? "Repeat your PIN" : "Create a PIN"; font.pixelSize: 38; w: 560 }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 156; text: o.hint !== "" ? o.hint : "Four digits, you use it to sign in"; font.pixelSize: 20; color: o.hint !== "" ? (Theme.dark ? "#FFB59E" : "#B3401C") : Theme.i62 }
            Row {
                id: pdots
                x: (parent.width - width) / 2; y: 270; spacing: 26
                Repeater { model: 4
                    Rectangle { width: 26; height: 26; radius: 13; color: o.pinNow.length > index ? Theme.acc : "transparent"; border.width: 3; border.color: o.pinNow.length > index ? Theme.acc : Theme.i5
                        scale: o.pinNow.length > index ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 180 } }
                        Behavior on color { ColorAnimation { duration: 180 } } } }
                SequentialAnimation { id: shake
                    NumberAnimation { target: pdots; property: "x"; to: pdots.x - 14; duration: 80 }
                    NumberAnimation { target: pdots; property: "x"; to: pdots.x + 14; duration: 80 }
                    NumberAnimation { target: pdots; property: "x"; to: (card.width - pdots.width) / 2; duration: 80 } }
            }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 360; text: "Type the digits on your keyboard"; font.pixelSize: 18; color: Theme.i5 }
        }

        // 3 look
        Item {
            anchors.fill: parent; visible: opacity > 0; opacity: o.step === 3 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 100; text: "Pick your look"; font.pixelSize: 38; w: 560 }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 156; text: "You can change it any time from the panel"; font.pixelSize: 20; color: Theme.i62 }
            Row {
                x: (parent.width - width) / 2; y: 225; spacing: 60
                Repeater { model: [false, true]
                    Item {
                        required property bool modelData
                        width: 290; height: 235
                        LookPreview { dark: parent.modelData; selected: Theme.dark === parent.modelData; onPicked: Theme.setDark(parent.modelData, o.persist) }
                        T { anchors.horizontalCenter: parent.horizontalCenter; y: 208; text: parent.modelData ? "Dark" : "Light"; font.pixelSize: 22; w: 560 }
                    } }
            }
            Pill { anchors.horizontalCenter: parent.horizontalCenter; y: 495; label: "Next"; onClicked: o.goto(4) }
        }

        // 4 keyboard
        Item {
            anchors.fill: parent; visible: opacity > 0; opacity: o.step === 4 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 80; text: "Your keyboard"; font.pixelSize: 38; w: 560 }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 134; text: "Add every language you type in, you can change it later in Settings"; font.pixelSize: 20; color: Theme.i62 }
            LayoutPicker { id: kb; x: (parent.width - width) / 2; y: 185; width: 640; listHeight: 110 }
            Pill { anchors.horizontalCenter: parent.horizontalCenter; y: 505; label: "Finish"; onClicked: o.finish() }
        }

        // 4 working and 5 done
        Item {
            anchors.fill: parent; visible: opacity > 0; opacity: o.step >= 5 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            Spinner { anchors.horizontalCenter: parent.horizontalCenter; y: 150; width: 84; height: 84; opacity: o.step === 5 ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 250 } } }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 280; text: o.step === 5 ? "Setting things up" : "You are all set"; font.pixelSize: 38; w: 560 }
            T { anchors.horizontalCenter: parent.horizontalCenter; y: 340; text: o.step === 5 ? "Just a moment" : "Hello, " + o.nameText.trim(); font.pixelSize: 22; color: Theme.i62 }
        }
    }
}
