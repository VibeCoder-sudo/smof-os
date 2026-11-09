import QtQuick
import QtQuick.Effects

// a small picture of the desktop in one theme: wallpaper, top bar, a window and the dock
Item {
    id: lp
    property bool dark: false
    property bool selected: false
    signal picked()
    width: 290
    height: 190
    scale: ma.containsMouse ? 1.03 : 1
    Behavior on scale { NumberAnimation { duration: 210; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] } }

    Item {
        id: pic
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: msk }

        Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true; sourceSize: Qt.size(580, 380)
            source: "file:///usr/share/smof/" + (lp.dark ? "dark" : "light") + "_sky.jpg" }
        Item {
            // the wallpaper layers, drawn at the design size and scaled down
            width: 1440; height: 1024; scale: lp.width / 1440; transformOrigin: Item.TopLeft
            Repeater {
                model: [1, 3, 4]
                Image { x: -62; y: -60; width: 1680; height: 1144; mipmap: true; sourceSize: Qt.size(560, 380); required property int modelData
                    source: "file:///usr/share/smof/" + (lp.dark ? "dark" : "light") + "_dune" + modelData + ".webp" }
            }
        }
        // top bar, two pills
        Rectangle { x: 10; y: 9; width: 78; height: 15; radius: 7.5; color: lp.dark ? "#6B0A081F" : "#4D281E50" }
        Rectangle { x: 212; y: 9; width: 68; height: 15; radius: 7.5; color: lp.dark ? "#6B0A081F" : "#4D281E50" }
        // a window with a frame
        Rectangle { x: 70; y: 44; width: 150; height: 92; radius: 8; color: lp.dark ? "#2A2060" : "#6B4FA8"
            Rectangle { x: 6; y: 5; width: 40; height: 4; radius: 2; color: "#FFFFFF"; opacity: .85 }
            Rectangle { x: 3; y: 16; width: parent.width - 6; height: parent.height - 19; radius: 4; color: "#252525"
                Rectangle { x: 8; y: 8; width: 60; height: 3; radius: 1.5; color: "#C9C9C9"; opacity: .7 }
                Rectangle { x: 8; y: 17; width: 90; height: 3; radius: 1.5; color: "#C9C9C9"; opacity: .45 }
                Rectangle { x: 8; y: 26; width: 44; height: 3; radius: 1.5; color: "#C9C9C9"; opacity: .45 } } }
        // dock
        Rectangle { x: (lp.width - 112) / 2; y: 158; width: 112; height: 24; radius: 12; color: lp.dark ? "#8F22194B" : "#80FFFFFF"
            Row { anchors.centerIn: parent; spacing: 6
                Rectangle { width: 14; height: 14; radius: 4; color: lp.dark ? "#4A3C86" : "#E4DAF8" }
                Rectangle { width: 14; height: 14; radius: 4; color: lp.dark ? "#4A3C86" : "#E4DAF8" }
                Rectangle { width: 14; height: 14; radius: 4; color: lp.dark ? "#4A2B34" : "#FFE1D6" }
                Rectangle { width: 14; height: 14; radius: 4; color: lp.dark ? "#4D4222" : "#FFF1C9" } } }
    }
    Item { id: msk; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: 26 } }

    // selection ring and a check
    Rectangle {
        anchors.fill: parent; anchors.margins: -6; radius: 32; color: "transparent"
        border.width: 4; border.color: Theme.acc
        opacity: lp.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 270; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } }
    }
    Rectangle {
        x: parent.width - 40; y: 10; width: 30; height: 30; radius: 15; color: Theme.acc
        scale: lp.selected ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 330; easing.type: Easing.OutBack } }
        Canvas { anchors.fill: parent; onPaint: { var c = getContext("2d"); c.reset(); c.strokeStyle = String(Theme.onacc); c.lineWidth = 3; c.lineCap = "round"; c.lineJoin = "round"
            c.beginPath(); c.moveTo(9, 15.5); c.lineTo(13.5, 20); c.lineTo(21.5, 10.5); c.stroke() } }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: lp.picked() }
}
