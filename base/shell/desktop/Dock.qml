import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// floating dock: launchers on the left, open windows on the right. Click a window to bring it back, click the active one to minimize it.
PanelWindow {
    id: dock
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 120
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "smof-dock"
    color: "transparent"
    mask: Region { item: pill }

    readonly property var apps: [
        { icon: "terminal", tint: "moon", cmd: ["foot"] },
        { icon: "grid", tint: "moon", cmd: [], action: "launcher" },
        { icon: "sliders", tint: "sys", cmd: [], action: "settings" },
        { icon: "dockfolder", tint: "yel", cmd: [] }
    ]
    function tintColor(t) { return t === "sys" ? Theme.sysbg : (t === "yel" ? Theme.yelbg : Theme.moonbg) }
    function iconFor(appId, title) {
        if ((title || "") === "Settings") return "sliders"
        var a = (appId || "").toLowerCase()
        if (a.indexOf("foot") >= 0 || a.indexOf("term") >= 0) return "terminal"
        return "grid"
    }

    // tile size: 60 normally, smaller when many windows would not fit on the screen
    readonly property int count: dock.apps.length + ToplevelManager.toplevels.values.length
    readonly property real ts: {
        var win = ToplevelManager.toplevels.values.length > 0
        var avail = Math.max(300, dock.width - 64) - 28 - (win ? 2 : 0)
        var units = count + 0.2 * (count - 1) + (win ? 0.4 : 0)
        return Math.max(22, Math.min(60, Math.floor(avail / units)))
    }
    // when a window fills the screen the dock steps aside and comes back when the cursor touches the bottom edge
    readonly property var front: ToplevelManager.activeToplevel
    readonly property bool covered: !!front && !front.minimized && (front.fullscreen || (Ui.autohide && front.maximized))
    property bool reveal: false
    readonly property bool shown: !covered || reveal || Ui.menuOpen || Ui.launcherOpen
    onCoveredChanged: { if (covered) { reveal = true; dhideT.restart() } else { reveal = false; dhideT.stop() } }
    Timer { id: dhideT; interval: 900; onTriggered: if (!Ui.menuOpen) dock.reveal = false }
    PanelWindow {
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 3
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-dock-edge"
        color: "transparent"
        visible: dock.covered && !dock.shown
        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: { dock.reveal = true; dhideT.restart() } }
    }
    function launch(cmd) { Quickshell.execDetached({ command: cmd, workingDirectory: Quickshell.env("HOME") }) }

    // ---- context menu (right click) ----
    property var menuItems: []
    property Item menuAnchor: null
    property var pending: null
    // opening the same tile again closes its menu; anything else opens the new menu after the old one is gone
    function openMenu(item, entries) {
        if (ctx.visible && menuAnchor === item) { closeMenu(); return }
        Ui.panelOpen = false
        ctx.visible = false
        pending = { item: item, entries: entries }
        openT.restart()
    }
    function closeMenu() { ctx.visible = false; openT.stop(); Ui.menuOpen = false }
    Timer { id: openT; interval: 40; onTriggered: { if (dock.pending) { dock.menuItems = dock.pending.entries; dock.menuAnchor = dock.pending.item; ctx.visible = true; Ui.menuOpen = true } } }
    Connections { target: Ui; function onDismiss() { dock.closeMenu() } }

    function windowMenu(tl) {
        return [
            { header: tl.title || "Window" },
            { label: tl.minimized ? "Show" : "Minimize", run: function () { if (tl.minimized) { tl.minimized = false; tl.activate() } else tl.minimized = true } },
            { label: tl.maximized ? "Restore size" : "Maximize", run: function () { tl.maximized = !tl.maximized } },
            { label: "Full screen", run: function () { tl.fullscreen = !tl.fullscreen } },
            { sep: true },
            { label: "Close", danger: true, run: function () { tl.close() } }
        ]
    }
    function launcherMenu(app) {
        if (app.action === "launcher") return [ { label: "Show all apps", run: function () { Ui.launcherOpen = true } } ]
        if (app.action === "settings") return [ { label: "Open Settings", run: function () { Ui.openSettings() } } ]
        if (app.cmd.length) return [ { label: "New window", run: function () { dock.launch(app.cmd) } } ]
        return [ { header: "Soon" }, { label: "Not available yet", disabled: true } ]
    }

    IpcHandler {
        target: "dock"
        function run(i: int): void { var a = dock.apps[i]; if (a && a.cmd.length) dock.launch(a.cmd) }
        function launcher(i: int): void { dock.openMenu(row.children[i], dock.launcherMenu(dock.apps[i])) }
        function window(i: int): void { var tl = ToplevelManager.toplevels.values[i]; if (tl) dock.openMenu(winRep.itemAt(i), dock.windowMenu(tl)) }
    }

    PopupWindow {
        id: ctx
        anchor.window: dock
        anchor.item: dock.menuAnchor
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        implicitWidth: 250
        implicitHeight: col.implicitHeight + 16
        color: "transparent"
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: 8
            radius: 22
            color: Theme.panelbg
            border.color: Theme.glassBorder
            Column {
                id: col
                x: 8; y: 8; width: parent.width - 16
                Repeater {
                    model: dock.menuItems
                    Item {
                        required property var modelData
                        width: col.width
                        height: modelData.sep ? 13 : 44
                        Rectangle { visible: !!modelData.sep; anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: Theme.i12 }
                        Rectangle {
                            visible: !modelData.sep && !modelData.header
                            anchors.fill: parent
                            radius: 14
                            color: Theme.acc
                            opacity: (!modelData.disabled && mm.containsMouse) ? .16 : 0
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }
                        T {
                            visible: !modelData.sep
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28; elide: Text.ElideRight
                            text: modelData.header || modelData.label || ""
                            font.pixelSize: modelData.header ? 14 : 17
                            w: modelData.header ? 560 : 460
                            color: modelData.header ? Theme.i55 : (modelData.disabled ? Theme.i5 : (modelData.danger ? (Theme.dark ? "#FFB59E" : "#B3401C") : Theme.ink))
                        }
                        MouseArea {
                            id: mm
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !modelData.sep && !modelData.header && !modelData.disabled
                            onClicked: { var f = modelData.run; dock.closeMenu(); if (f) f() }
                        }
                    }
                }
            }
        }
    }

    component Tile: Item {
        id: tile
        property string icon: ""
        property color bg: Theme.moonbg
        property bool active: false
        property bool dim: false
        signal clicked()
        signal rightClicked()
        width: dock.ts; height: dock.ts
        scale: ma.pressed ? .95 : (ma.containsMouse ? 1.07 : 1)
        opacity: dim ? .55 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Rectangle { anchors.fill: parent; radius: tile.width / 3; color: tile.bg; Behavior on color { ColorAnimation { duration: 400 } } }
        Rectangle { anchors.fill: parent; radius: tile.width / 3; color: "transparent"; border.width: 2; border.color: Theme.acc; visible: tile.active }
        Image {
            anchors.centerIn: parent
            width: tile.width * 0.47; height: width
            sourceSize: Qt.size(84, 84)
            source: "file:///usr/share/smof/icons/" + tile.icon + Theme.sfx + ".svg"
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => { if (m.button === Qt.RightButton) tile.rightClicked(); else tile.clicked() } }
    }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dock.shown ? 24 : -120
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        HoverHandler { onHoveredChanged: { if (dock.covered) { if (hovered) { dock.reveal = true; dhideT.stop() } else dhideT.restart() } } }
        width: row.implicitWidth + 28
        height: dock.ts + 20
        radius: height * 0.4
        opacity: Ui.entered ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: 600 } NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } }
        color: Theme.glass
        border.color: Theme.glassBorder
        Behavior on color { ColorAnimation { duration: 400 } }
        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: dock.ts * 0.2
            Repeater {
                model: dock.apps
                Tile {
                    icon: modelData.icon
                    bg: dock.tintColor(modelData.tint)
                    onClicked: { if (modelData.action === "settings") Ui.openSettings(); else if (modelData.action === "launcher") Ui.launcherOpen = !Ui.launcherOpen; else if (modelData.cmd.length) dock.launch(modelData.cmd) }
                    onRightClicked: dock.openMenu(this, dock.launcherMenu(modelData))
                }
            }
            Rectangle {
                visible: ToplevelManager.toplevels.values.length > 0
                width: 2; height: dock.ts * 0.67; radius: 1; color: Theme.i12
                anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
                id: winRep
                model: ToplevelManager.toplevels
                Tile {
                    required property var modelData
                    icon: dock.iconFor(modelData.appId, modelData.title)
                    bg: Theme.moonbg
                    active: modelData.activated
                    dim: modelData.minimized
                    onRightClicked: dock.openMenu(this, dock.windowMenu(modelData))
                    onClicked: {
                        if (modelData.minimized) { modelData.minimized = false; modelData.activate() }
                        else if (modelData.activated) modelData.minimized = true
                        else modelData.activate()
                    }
                }
            }
        }
    }
}
