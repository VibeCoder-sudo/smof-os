import QtQuick
import QtQuick.Effects

Item {
    id: ci
    property alias source: img.source
    width: 84
    height: 84
    Image { id: img; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: mask } }
    Item { id: mask; anchors.fill: parent; visible: false; layer.enabled: true
        Rectangle { anchors.fill: parent; radius: width / 2 } }
}
