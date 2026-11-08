import Quickshell
import Quickshell.Wayland
import QtQuick

// small cards at the top right for new notifications, they slide in and go away by themselves
PanelWindow {
    id: tw
    anchors { top: true; right: true }
    margins { top: 68; right: 16 }
    implicitWidth: 380
    implicitHeight: Math.max(1, col.implicitHeight)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "smof-toasts"
    color: "transparent"
    visible: Notifs.toasts.count > 0 && !Notifs.panelOpen
    mask: Region { item: col }

    Column {
        id: col
        width: 380
        spacing: 8
        move: Transition { NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutCubic } }
        Repeater {
            model: Notifs.toasts
            Item {
                id: slot
                required property real nid
                required property string app
                required property string summary
                required property string body
                required property string level
                required property bool hide
                required property string actions
                property bool shown: false
                Component.onCompleted: shown = true
                readonly property var acts: { try { return JSON.parse(actions) } catch (e) { return [] } }
                readonly property real baseH: Math.max(72, tx.implicitHeight + 28)
                // only a toast that has buttons grows when the cursor is on it
                property real extra: (acts.length > 0 && hh.hovered && !hide) ? 54 : 0
                Behavior on extra { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                width: 380
                height: baseH + extra
                readonly property bool on: shown && !hide
                HoverHandler { id: hh; onHoveredChanged: Notifs.setHover(slot.nid, hovered) }
                Rectangle {
                    id: toast
                    width: 380
                    height: parent.height
                    radius: 26
                    color: Theme.menubg
                    x: slot.on ? 0 : 70
                    opacity: slot.on ? 1 : 0
                    Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                    border.color: slot.level === "info" ? Theme.glassBorder : Theme.lvFg(slot.level)
                    border.width: slot.level === "info" ? 1 : 2
                    MouseArea { anchors.fill: parent; onClicked: Notifs.hideToast(slot.nid) }
                    Rectangle {
                        x: 14; y: (slot.baseH - 44) / 2
                        width: 44; height: 44; radius: 22; color: Theme.lvBg(slot.level)
                        T { anchors.centerIn: parent; text: slot.level === "info" ? (slot.app || "?").charAt(0).toUpperCase() : "!"; w: 700; font.pixelSize: slot.level === "info" ? 20 : 24; color: Theme.lvFg(slot.level) }
                    }
                    Column {
                        id: tx
                        x: 70; y: (slot.baseH - implicitHeight) / 2
                        width: parent.width - 70 - 16
                        spacing: 1
                        T { text: slot.summary; w: 560; font.pixelSize: 17; elide: Text.ElideRight; width: parent.width }
                        T { visible: text !== ""; text: slot.body; font.pixelSize: 15; color: Theme.i62; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; width: parent.width }
                    }
                    // the buttons the app gave
                    Row {
                        x: 70; y: slot.baseH - 4
                        spacing: 8
                        opacity: (slot.acts.length > 0 && hh.hovered && !slot.hide) ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 110 } }
                        Repeater {
                            model: slot.acts
                            Item {
                                required property var modelData
                                width: bt.implicitWidth + 28; height: 38
                                Rectangle { anchors.fill: parent; radius: 19; color: Theme.lvBg("info"); Rectangle { anchors.fill: parent; radius: 19; color: Theme.acc; opacity: bma.containsMouse ? .16 : 0 } }
                                T { id: bt; anchors.centerIn: parent; text: modelData.text; w: 560; font.pixelSize: 15; color: Theme.acc }
                                MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; enabled: hh.hovered && !slot.hide; onClicked: Notifs.invoke(slot.nid, modelData.id) }
                            }
                        }
                    }
                }
            }
        }
    }
}
