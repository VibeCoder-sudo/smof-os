import QtQuick
import QtQuick.Effects

// frosted glass: blurred wallpaper behind (when a backdrop is set), tint and a light border on top
Item {
    id: g
    property real radius: 28
    property int tick: 0
    readonly property Item bd: Backdrop.item

    FrameAnimation { running: g.visible && g.opacity > 0.01 && g.bd !== null; onTriggered: g.tick++ }

    Item {
        anchors.fill: parent
        layer.enabled: g.bd !== null
        layer.smooth: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: gmask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        ShaderEffectSource {
            anchors.fill: parent
            visible: g.bd !== null
            sourceItem: g.bd
            sourceRect: {
                g.tick
                if (!g.bd) return Qt.rect(0, 0, 1, 1)
                var a = g.bd.mapFromItem(g, 0, 0)
                var b = g.bd.mapFromItem(g, g.width, g.height)
                return Qt.rect(a.x, a.y, b.x - a.x, b.y - a.y)
            }
            live: true
            smooth: true
        }
    }
    Item {
        id: gmask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        Rectangle { anchors.fill: parent; radius: g.radius; antialiasing: true }
    }
    Rectangle {
        anchors.fill: parent
        radius: g.radius
        antialiasing: true
        color: Theme.glass
        border.color: Theme.glassBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: 400 } }
    }
}
