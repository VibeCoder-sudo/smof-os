import Quickshell
import Quickshell.Wayland
import QtQuick

// app list: opens from the grid tile in the dock. Smof's own apps first, then everything with a .desktop entry. Type to search.
PanelWindow {
    id: lw
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "smof-launcher"
    WlrLayershell.keyboardFocus: Ui.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    visible: Ui.launcherOpen || root.opacity > 0.01

    function home(cmd) { Quickshell.execDetached({ command: cmd, workingDirectory: Quickshell.env("HOME") }) }
    function close() { Ui.launcherOpen = false }

    readonly property var builtins: [
        { name: "Terminal", glyph: "terminal", run: function () { lw.home(["foot"]) } },
        { name: "Settings", glyph: "sliders", run: function () { Ui.openSettings() } }
    ]
    readonly property var hidden: ["foot", "foot client", "foot server", "quickshell"]

    // the list shown: built in apps and desktop entries, filtered by the search text
    readonly property var items: {
        var q = search.text.trim().toLowerCase()
        var out = []
        var b = lw.builtins
        for (var i = 0; i < b.length; i++) if (q === "" || b[i].name.toLowerCase().indexOf(q) >= 0) out.push(b[i])
        var rest = []
        var ds = DesktopEntries.applications.values
        for (var k = 0; k < ds.length; k++) {
            var e = ds[k]
            if (e.noDisplay) continue
            var n = (e.name || "")
            if (n === "" || lw.hidden.indexOf(n.toLowerCase()) >= 0) continue
            if (q !== "" && n.toLowerCase().indexOf(q) < 0 && (e.genericName || "").toLowerCase().indexOf(q) < 0) continue
            rest.push({ name: n, icon: e.icon, entry: e })
        }
        rest.sort(function (a, c) { return a.name.localeCompare(c.name) })
        return out.concat(rest)
    }
    function launchItem(it) {
        if (!it) return
        lw.close()
        if (it.run) { it.run(); return }
        if (!it.entry) return
        // apps start with the accessibility switches on, so their menus can show in the top bar
        var cmd = it.entry.command
        if (cmd && cmd.length > 0 && !it.entry.runInTerminal)
            Quickshell.execDetached({ command: ["env", "QT_ACCESSIBILITY=1", "QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1", "GTK_A11Y=atspi"].concat(cmd), workingDirectory: it.entry.workingDirectory || Quickshell.env("HOME") })
        else it.entry.execute()
    }

    onVisibleChanged: if (visible && Ui.launcherOpen) { search.text = ""; search.forceActiveFocus() }
    Connections { target: Ui; function onLauncherOpenChanged() { if (Ui.launcherOpen) { search.text = ""; search.forceActiveFocus() } } }

    Item {
        id: root
        anchors.fill: parent
        opacity: Ui.launcherOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        focus: true
        Keys.onEscapePressed: lw.close()

        // dim backdrop, a click on it closes
        Rectangle { anchors.fill: parent; color: Theme.dark ? "#000000" : "#FFFFFF"; opacity: Theme.dark ? .38 : .30 }
        MouseArea { anchors.fill: parent; onClicked: lw.close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(1020, parent.width - 160)
            height: Math.min(700, parent.height - 220)
            radius: 36
            color: Theme.panelbg
            border.color: Theme.glassBorder
            scale: Ui.launcherOpen ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }   // clicks inside do not close

            // search
            Rectangle {
                id: sbox
                x: 28; y: 28; width: parent.width - 56; height: 52; radius: 26
                color: Theme.glass2
                T { visible: search.text === ""; x: 52; anchors.verticalCenter: parent.verticalCenter; text: "Search apps"; font.pixelSize: 18; color: Theme.i5 }
                Image { x: 18; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sourceSize: Qt.size(60, 60); opacity: .7
                    source: "file:///usr/share/smof/icons/grid" + Theme.sfx + ".svg" }
                TextInput {
                    id: search
                    x: 52; width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                    font.family: "Google Sans Flex"; font.pixelSize: 18; color: Theme.ink
                    clip: true
                    selectByMouse: true
                    Keys.onEscapePressed: lw.close()
                    Keys.onReturnPressed: lw.launchItem(lw.items[0])
                    onTextChanged: grid.positionViewAtBeginning()
                }
            }

            GridView {
                id: grid
                x: 20; y: 100
                width: parent.width - 40; height: parent.height - 120
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 150)))
                cellHeight: 150
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: lw.items
                delegate: Item {
                    id: tile
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    readonly property string path: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                    Rectangle { anchors.fill: parent; anchors.margins: 6; radius: 24; color: Theme.acc; opacity: tma.pressed ? .2 : (tma.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 100 } } }
                    Item {
                        x: (parent.width - 72) / 2; y: 18; width: 72; height: 72
                        // real icon when the theme has one
                        Image { anchors.fill: parent; visible: tile.path !== ""; source: tile.path; sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectFit; smooth: true }
                        // our own glyph tile, or a letter
                        Rectangle {
                            visible: tile.path === ""
                            anchors.fill: parent; radius: 24
                            color: modelData.glyph === "sliders" ? Theme.sysbg : Theme.moonbg
                            Image { visible: !!modelData.glyph; anchors.centerIn: parent; width: 34; height: 34; sourceSize: Qt.size(102, 102); source: modelData.glyph ? "file:///usr/share/smof/icons/" + modelData.glyph + Theme.sfx + ".svg" : "" }
                            T { visible: !modelData.glyph; anchors.centerIn: parent; text: (modelData.name || "?").charAt(0).toUpperCase(); w: 600; font.pixelSize: 30; color: Theme.acc }
                        }
                    }
                    T { x: 10; y: 100; width: parent.width - 20; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.pixelSize: 15; elide: Text.ElideRight; maximumLineCount: 1 }
                    MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; onClicked: lw.launchItem(modelData) }
                }
                T { visible: lw.items.length === 0; anchors.centerIn: parent; text: "No apps match"; font.pixelSize: 18; color: Theme.i55 }
            }
        }
    }
}
