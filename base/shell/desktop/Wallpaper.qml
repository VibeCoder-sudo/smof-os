import QtQuick

// dunes wallpaper in layers with a slow sway. Both themes can be on screen while the theme changes, the fading one unloads after.
Item {
    id: wp
    property real depth: 0          // 0 lock, 1 login, 2 desktop
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
        active: !Theme.dark || opacity > 0.01
        opacity: Theme.dark ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 1200 } }
        property string themeName: "light"
        sourceComponent: set
    }
    Loader {
        id: darkL
        anchors.fill: parent
        active: Theme.dark || opacity > 0.01
        opacity: Theme.dark ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 1200 } }
        property string themeName: "dark"
        sourceComponent: set
    }
}
