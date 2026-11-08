import QtQuick

// icon from /usr/share/smof/icons, the dark variant is picked by the theme unless `fixed` is set
Image {
    property string name: ""
    property bool fixed: false
    sourceSize: Qt.size(width * 3, height * 3)
    source: "file:///usr/share/smof/icons/" + name + (fixed ? "" : Theme.sfx) + ".svg"
}
