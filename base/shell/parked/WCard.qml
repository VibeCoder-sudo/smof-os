import QtQuick

Glass {
    id: wc
    property bool on: false
    property real slide: on ? 0 : 60
    Behavior on slide { NumberAnimation { duration: wc.on ? 550 : 300; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: wc.on ? 500 : 300; easing.type: Easing.OutCubic } }
    opacity: on ? 1 : 0
    transform: [Translate { x: wc.slide }, Scale { origin.x: wc.width / 2; origin.y: wc.height / 2; xScale: wc.on ? 1 : .96; yScale: wc.on ? 1 : .96 }]
}
