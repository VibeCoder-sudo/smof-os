import QtQuick

Glass {
    id: card
    property string kind: "mj"
    property string title: ""
    property string msg: ""
    property string extra: ""
    property string ts: ""
    property bool on: false
    property real slide: on ? 0 : -60
    Behavior on slide { NumberAnimation { duration: card.on ? 550 : 300; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: card.on ? 500 : 300; easing.type: Easing.OutCubic } }
    opacity: on ? 1 : 0
    transform: Translate { x: card.slide }
    width: 560
    height: 118

    // avatar
    Loader {
        x: 16; y: 17; width: 84; height: 84
        sourceComponent: card.kind === "mj" ? mjAv : iconAv
    }
    Component { id: mjAv; CircleImage { source: "file:///usr/share/smof/mj.jpg" } }
    Component {
        id: iconAv
        Rectangle {
            radius: 42
            color: card.kind === "sys" ? Theme.sysbg : Theme.pxbg
            Image { anchors.centerIn: parent; width: 40; height: 40; sourceSize: Qt.size(96, 96)
                source: "file:///usr/share/smof/icons/" + (card.kind === "sys" ? "shield" : "phone") + Theme.sfx + ".svg" }
        }
    }

    T { x: 116; y: 26; w: 560; text: card.title; font.pixelSize: 28; font.weight: Font.DemiBold }
    T { x: 116 + titleW + 12; y: 33; visible: card.extra !== ""; text: card.extra; font.pixelSize: 18; color: Theme.i5 }
    readonly property real titleW: fm.advanceWidth(card.title)
    FontMetrics { id: fm; font.family: "Google Sans Flex"; font.pixelSize: 28; font.weight: Font.DemiBold }

    Image { x: 116; y: 67; width: 22; height: 22; visible: card.kind === "px"; sourceSize: Qt.size(66, 66); opacity: .62
        source: "file:///usr/share/smof/icons/folder" + Theme.sfx + ".svg" }
    T { x: card.kind === "px" ? 144 : 116; y: 64; text: card.msg; font.pixelSize: 22; color: Theme.i62 }

    T { anchors.right: parent.right; anchors.rightMargin: 24; y: 31; text: card.ts; font.pixelSize: 18; color: Theme.i5 }
}
