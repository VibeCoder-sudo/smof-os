import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// Smof wallpaper: the dunes, fading in from the dark start colour, plus the software brightness veil
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "smof-wallpaper"
        id: wallWin
        IpcHandler { target: "desktop"
            function menu(x: int, y: int): void { wallWin.openMenu(x, y) }
            function addapp(spec: string, x: int, y: int): void { icons.addApp(spec, x, y) }
            function refresh(): void { icons.refresh() } }
        color: "#0f0d16"

        // ---- right click on the desktop, and files dropped on it ----
        property var desk: []
        property real mx: 0
        property real my: 0
        readonly property string home: Quickshell.env("HOME")
        function sh(args) { Quickshell.execDetached({ command: args, workingDirectory: home }) }
        function openMenuWith(x, y, entries) {
            desk = entries
            mx = x; my = y
            deskPop.visible = false
            deskT.restart()
        }
        function openMenu(x, y) {
            desk = [
                { label: "New folder", run: function () { wallWin.sh(["/usr/local/bin/smof-fileops", "mkdir", wallWin.home + "/Desktop", "New Folder"]) } },
                { label: "Clean up icons", run: function () { icons.cleanUp() } },
                { label: "Open Files", run: function () { wallWin.sh(["/usr/local/bin/smof-files", wallWin.home + "/Desktop"]) } },
                { label: "Open Terminal", run: function () { wallWin.sh(["foot"]) } },
                { sep: true },
                { label: "Change wallpaper", run: function () { wallWin.sh(["/usr/local/bin/smof-settings", "wallpaper"]) } },
                { label: Theme.dark ? "Switch to light" : "Switch to dark", run: function () { Theme.toggle() } },
                { label: "Settings", run: function () { wallWin.sh(["/usr/local/bin/smof-settings", ""]) } }
            ]
            mx = x; my = y
            deskPop.visible = false
            deskT.restart()
        }
        Timer { id: deskT; interval: 30; onTriggered: deskPop.visible = true }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons
            onPressed: (m) => { if (m.button === Qt.RightButton) wallWin.openMenu(m.x, m.y); else { deskPop.visible = false; icons.clearSel() } } }
        DropArea {
            anchors.fill: parent
            onDropped: (d) => {
                if (!d.hasUrls) return
                var ps = []
                for (var i = 0; i < d.urls.length; i++) { var u = d.urls[i].toString(); if (u.indexOf("file://") === 0) ps.push(decodeURIComponent(u.slice(7))) }
                if (ps.length === 0) return
                d.acceptProposedAction()
                icons.dropped(ps.filter(function (p) { return p.indexOf(wallWin.home + "/Desktop/") !== 0 }), d.x, d.y, d.proposedAction === Qt.CopyAction)
            }
        }
        PopupWindow {
            id: deskPop
            anchor.window: wallWin
            anchor.rect: Qt.rect(wallWin.mx, wallWin.my, 1, 1)
            anchor.edges: Edges.Top | Edges.Left
            anchor.gravity: Edges.Bottom | Edges.Right
            implicitWidth: 270
            implicitHeight: dcol.implicitHeight + 16
            color: "transparent"
            visible: false
            Rectangle {
                anchors.fill: parent; radius: 20; color: Theme.menubg; border.color: Theme.glassBorder
                Column {
                    id: dcol
                    x: 8; y: 8; width: parent.width - 16
                    Repeater {
                        model: wallWin.desk
                        Item {
                            required property var modelData
                            width: dcol.width; height: modelData.sep ? 13 : 38
                            Rectangle { visible: !!modelData.sep; anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: Theme.i12 }
                            Rectangle { visible: !modelData.sep; anchors.fill: parent; radius: 13; color: Theme.acc; opacity: dm.containsMouse ? .16 : 0 }
                            T { visible: !modelData.sep; x: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.label || ""; font.pixelSize: 16; w: 460 }
                            MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; enabled: !modelData.sep
                                onClicked: { var f = modelData.run; deskPop.visible = false; if (f) f() } }
                        }
                    }
                }
            }
        }
        Item {
            anchors.fill: parent
            opacity: Ui.entered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 1000; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } }
            Item {
                width: 1440; height: 1024; anchors.centerIn: parent
                scale: Math.max(parent.width / 1440, parent.height / 1024)
                Wallpaper { x: -62; y: -60; depth: 2 }
            }
            Rectangle { anchors.fill: parent; color: "#000000"; opacity: Look.wpDim }
        }
        DesktopIcons { id: icons; anchors.fill: parent; opacity: Ui.entered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 1000; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } }
            onMenuRequested: (x, y, e) => wallWin.openMenuWith(x, y, e) }
    }

    // the dragged desktop icon, above the dock so it can be seen all the way
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-desktop-ghost"
        color: "transparent"
        visible: icons.ghostOn
        mask: Region {}
        Item {
            x: icons.ghostX; y: icons.ghostY; width: 116; height: 124
            Image { x: 26; y: 14; width: 64; height: 64; sourceSize: Qt.size(192, 192); fillMode: Image.PreserveAspectFit; source: icons.ghostSrc; opacity: .96 }
            Text { x: 7; y: 86; width: 102; horizontalAlignment: Text.AlignHCenter; text: icons.ghostLabel; font.pixelSize: 14; color: "#FFFFFF"; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; font.family: "Google Sans Flex" }
        }
    }

    // software brightness: a dark veil over everything, clicks go through
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-dimmer"
        color: "transparent"
        visible: Ui.brightness < 0.999
        mask: Region {}
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 1 - Ui.brightness }
    }
}
