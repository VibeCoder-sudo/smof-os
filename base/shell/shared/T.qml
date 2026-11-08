import QtQuick

// Text with the system font, weight set by `w`
Text {
    property int w: 400
    color: Theme.ink
    font.family: "Google Sans Flex"
    font.variableAxes: ({ "wght": w, "opsz": 18 })
    renderType: Text.QtRendering
}
