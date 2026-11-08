import QtQuick

// dunes wallpaper in layers with a slow sway. Both themes can be on screen while the theme changes, the fading one unloads after.
Item {
    id: wp
    property real depth: 0          // 0 lock, 1 login, 2 desktop
    property string scope: "desktop"   // "lock" follows the lock screen choice, anything else the desktop one
    readonly property string mode: scope === "lock" ? (Look.lockMode === "same" ? Look.wpMode : Look.lockMode) : Look.wpMode
    readonly property string image: scope === "lock" && Look.lockMode === "image" ? Look.lockImage : Look.wpImage
    readonly property var grad: { for (var i = 0; i < Look.gradients.length; i++) if (Look.gradients[i].id === mode) return Look.gradients[i]; return null }
    readonly property var amps: [10, 16, 22, 30, 40]
    readonly property var secs: [34, 28, 26, 22, 19]
    width: 1680
    height: 1144

    Component {
        id: set
        Item {
            id: s
            property string theme: parent.themeName
            anchors.fill: parent
            Image { anchors.fill: parent; mipmap: true; smooth: true; sourceSize: Qt.size(2520, 1716); source: "file:///usr/share/smof/" + s.theme + "_sky.jpg" }
            Repeater {
                model: 5
                Item {
                    width: wp.width
                    height: wp.height
                    y: wp.depth * (index + 1) * 4
                    Behavior on y { NumberAnimation { duration: 1100; easing.type: Easing.OutCubic } }
                    Image {
                        mipmap: true
                        smooth: true
                        sourceSize: Qt.size(2520, 1716)
                        width: parent.width
                        height: parent.height
                        source: "file:///usr/share/smof/" + s.theme + "_dune" + index + ".webp"
                        SequentialAnimation on x {
                            loops: Animation.Infinite
                            paused: Ui.calm
                            NumberAnimation { from: -wp.amps[index]; to: wp.amps[index]; duration: wp.secs[index] * 1000; easing.type: Easing.InOutSine }
                            NumberAnimation { from: wp.amps[index]; to: -wp.amps[index]; duration: wp.secs[index] * 1000; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: lightL
        anchors.fill: parent
        active: wp.mode === "dunes" && (!Theme.dark || opacity > 0.01)
        opacity: Theme.dark ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 1200 } }
        property string themeName: "light"
        sourceComponent: set
    }
    Loader {
        id: darkL
        anchors.fill: parent
        active: wp.mode === "dunes" && (Theme.dark || opacity > 0.01)
        opacity: Theme.dark ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 1200 } }
        property string themeName: "dark"
        sourceComponent: set
    }

    Rectangle {
        visible: wp.grad !== null
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: wp.grad ? (Theme.dark ? wp.grad.d1 : wp.grad.l1) : "transparent" }
            GradientStop { position: 1; color: wp.grad ? (Theme.dark ? wp.grad.d2 : wp.grad.l2) : "transparent" }
        }
    }
    Image {
        visible: wp.mode === "image" && wp.image !== ""
        anchors.fill: parent
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(2520, 1716)
        source: wp.mode === "image" && wp.image !== "" ? "file://" + wp.image : ""
    }
}
