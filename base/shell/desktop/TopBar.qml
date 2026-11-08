import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// two floating pills at the top: logo, app name and menus on the left, status and clock on the right
PanelWindow {
    id: bar
    anchors { top: true; left: true; right: true }
    implicitHeight: 64
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "smof-bar"
    // above a full screen window, otherwise a normal panel
    WlrLayershell.layer: fs ? WlrLayer.Overlay : WlrLayer.Top
    color: "transparent"
    mask: Region { regions: [ Region { item: bar.shown ? leftPill : null }, Region { item: bar.shown ? rightPill : null } ] }

    // ---- state: the window in front, full screen auto hide ----
    readonly property var at: ToplevelManager.activeToplevel
    // a maximized window (title bar button, super+up) counts like full screen: the bar steps aside and takes no room
    readonly property bool fs: !!at && (at.fullscreen || (Ui.autohide && at.maximized))
    property bool reveal: false                 // the cursor is at the top edge or on the bar
    property bool menuUp: false
    readonly property bool shown: !fs || reveal || Ui.panelOpen || menuUp
    // in full screen the bar shows for a moment, then hides until the cursor goes to the top edge
    onFsChanged: { if (fs) { reveal = true; hideT.restart() } else { reveal = false; hideT.stop() } }
    Timer { id: hideT; interval: 900; onTriggered: if (!bar.menuUp) bar.reveal = false }
    function pointerOnBar(on) { if (!fs) return; if (on) { reveal = true; hideT.stop() } else hideT.restart() }

    function appName(tl) {
        if (!tl) return "Desktop"
        var a = (tl.appId || "").toLowerCase()
        if (a === "" || a.indexOf("quickshell") >= 0) return tl.title || "Smof"
        if (a === "foot" || a.indexOf("term") >= 0) return "Terminal"
        var de = DesktopEntries.heuristicLookup(tl.appId)
        if (de && de.name) return de.name
        var n = tl.appId || tl.title || "App"
        return n.charAt(0).toUpperCase() + n.slice(1)
    }

    // ---- the menus of the app in front, read through the accessibility bus by smof-menubridge ----
    property var appMenus: []                       // [{label, path, items: [...]}]
    Process {
        id: mb
        command: ["/usr/local/bin/smof-menubridge", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var o = JSON.parse(text); bar.appMenus = o.menus || [] } catch (e) { bar.appMenus = [] }
                if (bar.menuUp && bar.menuIndex >= 10) bar.menuItems = bar.entriesFor(bar.menuIndex)
            }
        }
    }
    function refreshMenus() { if (!mb.running) mb.running = true }
    Timer { id: mbT; interval: 250; onTriggered: bar.refreshMenus() }
    onAtChanged: { appMenus = []; mbT.restart() }
    // what the bar shows after the app name: the app's own menus, then ours that the app does not have by name
    readonly property var barMenus: {
        var out = [], used = {}
        var am = appMenus
        for (var i = 0; i < am.length; i++) { out.push({ label: am[i].label, id: 10 + i }); used[am[i].label.toLowerCase()] = true }
        var ours = [{ label: "File", id: 1 }, { label: "View", id: 2 }, { label: "Window", id: 3 }]
        for (var k = 0; k < ours.length; k++) if (!used[ours[k].label.toLowerCase()]) out.push(ours[k])
        return out
    }
    function menuEntries(items, depth, flat) {
        var out = []
        for (var i = 0; i < items.length; i++) {
            (function (it) {
                if (it.kind === "sep") { out.push({ sep: true }); return }
                var kids = it.children || []
                var e = { label: it.label, disabled: !it.enabled, check: it.kind === "check" && it.checked, hint: it.key || "", depth: depth, kids: kids, hasKids: kids.length > 0 && !flat }
                e.run = function () { Quickshell.execDetached(["/usr/local/bin/smof-menubridge", "press", it.path]) }
                out.push(e)
                if (flat && kids.length > 0) out = out.concat(menuEntries(kids, depth + 1, true))
            })(items[i])
        }
        return out
    }

    // ---- drop down menus ----
    property var menuItems: []
    property Item menuAnchor: null
    property int menuIndex: -1
    function entriesFor(i) {
        if (i >= 10) { var m = bar.appMenus[i - 10]; return m ? menuEntries(m.items, 0, false) : [] }
        var tl = bar.at
        var name = appName(tl)
        var win = ToplevelManager.toplevels.values
        if (i === 4) return [
            { label: "About Smof", run: function () { Quickshell.execDetached({ command: ["foot", "-e", "sh", "-c", "fastfetch; echo; printf 'press Enter to close '; read x"], workingDirectory: Quickshell.env("HOME") }) } },
            { label: "Settings...", run: function () { Ui.openSettings() } },
            { sep: true },
            { label: "Lock", run: function () { Quickshell.execDetached(["loginctl", "terminate-user", Quickshell.env("USER")]) } },
            { label: "Log Out", run: function () { Quickshell.execDetached(["loginctl", "terminate-user", Quickshell.env("USER")]) } },
            { label: "Shut Down", danger: true, run: function () { Quickshell.execDetached(["sudo", "-n", "/usr/bin/systemctl", "poweroff"]) } }
        ]
        var isTerm = !!tl && name === "Terminal"
        if (i === 0) {
            if (!tl) return [
                { header: "Smof" },
                { label: "About Smof", run: function () { Quickshell.execDetached({ command: ["foot", "-e", "sh", "-c", "fastfetch; echo; printf 'press Enter to close '; read x"], workingDirectory: Quickshell.env("HOME") }) } },
                { label: "Settings...", run: function () { Ui.openSettings() } }
            ]
            // an app menu only has what belongs to that app
            return [
                { header: name },
                { label: "Hide " + name, run: function () { tl.minimized = true } },
                { label: "Quit " + name, danger: true, run: function () { tl.close() } }
            ]
        }
        if (i === 1) {
            var f = [ { label: isTerm ? "New Terminal Window" : "New Window", disabled: !isTerm && !!tl, run: function () { Quickshell.execDetached({ command: ["foot"], workingDirectory: Quickshell.env("HOME") }) } } ]
            if (tl) { f.push({ sep: true }); f.push({ label: "Close Window", run: function () { tl.close() } }) }
            return f
        }
        if (i === 2) {
            // with an app in front: only how that window is shown; on the empty desktop: the system look
            if (tl) return [
                { label: tl.fullscreen ? "Exit Full Screen" : "Enter Full Screen", run: function () { tl.fullscreen = !tl.fullscreen } },
                { label: tl.maximized ? "Restore Size" : "Fill Screen", run: function () { tl.maximized = !tl.maximized } }
            ]
            return [
                { header: "Desktop" },
                { label: Theme.dark ? "Switch to Light" : "Switch to Dark", run: function () { Theme.toggle() } },
                { label: Ui.calm ? "Turn Calm mode off" : "Turn Calm mode on", run: function () { Ui.calm = !Ui.calm } },
                { label: Ui.dnd ? "Turn Focus off" : "Turn Focus on", run: function () { Ui.dnd = !Ui.dnd } }
            ]
        }
        var e = [
            { label: "Minimize", disabled: !tl, run: function () { tl.minimized = true } },
            { label: (tl && tl.maximized) ? "Restore size" : "Maximize", disabled: !tl, run: function () { tl.maximized = !tl.maximized } },
            { sep: true }
        ]
        if (win.length === 0) e.push({ label: "No open windows", disabled: true })
        for (var k = 0; k < win.length; k++) {
            (function (w) {
                var t = (w.title || w.appId || "Window")
                if (t.length > 30) t = t.slice(0, 29) + "..."
                e.push({ label: t, check: w.activated, run: function () { if (w.minimized) w.minimized = false; w.activate() } })
            })(win[k])
        }
        return e
    }
    function openMenu(i, item) {
        if (menuIndex === i && menuPop.visible) { closeMenu(); return }
        Ui.panelOpen = false
        menuPop.visible = false
        subPop.visible = false
        if (i >= 10) refreshMenus()
        menuItems = entriesFor(i)
        menuWide = i >= 10
        menuAnchor = item
        menuIndex = i
        openT.restart()
    }
    function closeMenu() { subPop.visible = false; menuPop.visible = false; openT.stop(); menuIndex = -1; menuUp = false; Ui.menuOpen = false; if (fs) hideT.restart() }
    property bool menuWide: false
    // a submenu opens to the right of the item in the first list
    property var subItems: []
    property Item subAnchor: null
    function openSub(item, kids) {
        if (!kids || kids.length === 0) { subPop.visible = false; return }
        if (subPop.visible && subAnchor === item) return
        subPop.visible = false
        subItems = menuEntries(kids, 0, true)
        subAnchor = item
        subT.restart()
    }
    Timer { id: subT; interval: 30; onTriggered: subPop.visible = true }
    Timer { id: openT; interval: 40; onTriggered: { menuPop.visible = true; bar.menuUp = true; Ui.menuOpen = true } }
    Connections { target: Ui; function onDismiss() { bar.closeMenu() } }

    IpcHandler {
        target: "bar"
        function menu(i: int): void { if (i === 0) bar.openMenu(0, btnApp); else if (i < 0) bar.openMenu(4, btnLogo); else { var b = menuRep.itemAt(i - 1); if (b) bar.openMenu(bar.barMenus[i - 1].id, b) } }
        function menus(): string { return JSON.stringify(bar.barMenus.map(function (m) { return m.label })) }
        function refresh(): void { bar.refreshMenus() }
        function reveal(): void { bar.reveal = true; hideT.restart() }
        function maximize(): void { if (bar.at) bar.at.maximized = !bar.at.maximized }
    }

    // a thin strip at the very top edge: the cursor touching it brings the bar back in full screen
    PanelWindow {
        anchors { top: true; left: true; right: true }
        implicitHeight: 3
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-edge"
        color: "transparent"
        visible: bar.fs && !bar.shown
        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: { bar.reveal = true; hideT.restart() } }
    }

    PopupWindow {
        id: menuPop
        anchor.window: bar
        anchor.item: bar.menuAnchor
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        implicitWidth: bar.menuWide ? 340 : 270
        implicitHeight: mcol.implicitHeight + 16
        color: "transparent"
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 8
            radius: 22
            color: Theme.panelbg
            border.color: Theme.glassBorder
            Column {
                id: mcol
                x: 8; y: 8; width: parent.width - 16
                Repeater {
                    model: bar.menuItems
                    Item {
                        required property var modelData
                        width: mcol.width
                        height: modelData.sep ? 13 : 42
                        Rectangle { visible: !!modelData.sep; anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: Theme.i12 }
                        Rectangle {
                            visible: !modelData.sep && !modelData.header
                            anchors.fill: parent
                            radius: 14
                            color: Theme.acc
                            opacity: (!modelData.disabled && mm.containsMouse) || (modelData.hasKids && bar.subAnchor === parent && subPop.visible) ? .16 : 0
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }
                        T {
                            visible: !modelData.sep
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28 - (modelData.hint ? 90 : 0) - (modelData.hasKids ? 18 : 0); elide: Text.ElideRight
                            text: (modelData.check ? "\u2713  " : "") + (modelData.header || modelData.label || "")
                            font.pixelSize: modelData.header ? 14 : 17
                            w: modelData.header ? 600 : 460
                            color: modelData.header ? Theme.i55 : (modelData.disabled ? Theme.i5 : (modelData.danger ? Theme.errfg : Theme.ink))
                        }
                        T { visible: !!modelData.hint; anchors.right: parent.right; anchors.rightMargin: modelData.hasKids ? 32 : 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.hint || ""; font.pixelSize: 14; color: Theme.i5 }
                        T { visible: !!modelData.hasKids; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "\u203A"; font.pixelSize: 22; color: Theme.i55 }
                        MouseArea {
                            id: mm
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !modelData.sep && !modelData.header && !modelData.disabled
                            onEntered: bar.openSub(parent, modelData.hasKids ? modelData.kids : [])
                            onClicked: {
                                if (modelData.hasKids) { bar.openSub(parent, modelData.kids); return }
                                var f = modelData.run; bar.closeMenu(); if (f) f()
                            }
                        }
                    }
                }
            }
        }
    }

    // submenu, to the right of the first list
    PopupWindow {
        id: subPop
        anchor.window: menuPop
        anchor.item: bar.subAnchor
        anchor.edges: Edges.Right | Edges.Top
        anchor.gravity: Edges.Right | Edges.Bottom
        implicitWidth: 320
        implicitHeight: scol.implicitHeight + 16
        color: "transparent"
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 6
            radius: 22
            color: Theme.panelbg
            border.color: Theme.glassBorder
            Column {
                id: scol
                x: 8; y: 8; width: parent.width - 16
                Repeater {
                    model: bar.subItems
                    Item {
                        required property var modelData
                        width: scol.width
                        height: modelData.sep ? 13 : 42
                        Rectangle { visible: !!modelData.sep; anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: Theme.i12 }
                        Rectangle { visible: !modelData.sep; anchors.fill: parent; radius: 14; color: Theme.acc; opacity: (!modelData.disabled && sm.containsMouse) ? .16 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
                        T {
                            visible: !modelData.sep
                            x: 14 + modelData.depth * 16; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28 - modelData.depth * 16 - (modelData.hint ? 90 : 0); elide: Text.ElideRight
                            text: (modelData.check ? "\u2713  " : "") + (modelData.label || "")
                            font.pixelSize: 17
                            w: 460
                            color: modelData.disabled ? Theme.i5 : Theme.ink
                        }
                        T { visible: !!modelData.hint; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.hint || ""; font.pixelSize: 14; color: Theme.i5 }
                        MouseArea {
                            id: sm
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !modelData.sep && !modelData.disabled
                            onClicked: { var f = modelData.run; bar.closeMenu(); if (f) f() }
                        }
                    }
                }
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    component Pill: Rectangle {
        height: 44
        radius: 22
        y: bar.shown ? 10 : -60
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        HoverHandler { onHoveredChanged: bar.pointerOnBar(hovered) }
        opacity: Ui.entered ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: 450 } NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } }
        color: Theme.pill
        border.color: "#33FFFFFF"
        Behavior on color { ColorAnimation { duration: 400 } }
    }
    component BarBtn: Item {
        id: b
        property alias label: t.text
        property bool bold: false
        signal clicked()
        signal entered()
        width: t.implicitWidth + 28
        height: 36
        Rectangle { anchors.fill: parent; radius: 18; color: "white"; opacity: ma.pressed ? .26 : (ma.containsMouse ? .16 : 0); Behavior on opacity { NumberAnimation { duration: 120 } } }
        T { id: t; anchors.centerIn: parent; color: "#FFFFFF"; font.pixelSize: 17; w: b.bold ? 600 : 460 }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked(); onEntered: b.entered() }
    }
    component IconBtn: Item {
        id: ib
        property string name: ""
        signal clicked()
        width: 36
        height: 36
        Rectangle { anchors.fill: parent; radius: 18; color: "white"; opacity: ma2.pressed ? .26 : (ma2.containsMouse ? .16 : 0); Behavior on opacity { NumberAnimation { duration: 120 } } }
        Ico { anchors.centerIn: parent; width: 20; height: 20; name: ib.name; fixed: true }
        MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; onClicked: ib.clicked() }
    }

    Pill {
        id: leftPill
        x: 16
        width: lrow.implicitWidth + 12
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Row {
            id: lrow
            x: 6
            height: parent.height
            spacing: 2
            Item {
                id: btnLogo
                width: 36; height: 36; anchors.verticalCenter: parent.verticalCenter
                Rectangle { anchors.fill: parent; radius: 18; color: "white"; opacity: lma.pressed ? .26 : (lma.containsMouse || bar.menuIndex === 4 ? .16 : 0); Behavior on opacity { NumberAnimation { duration: 120 } } }
                Rectangle { anchors.centerIn: parent; width: 24; height: 24; radius: 12
                    gradient: Gradient { GradientStop { position: 0; color: "#F6B8D4" } GradientStop { position: 1; color: "#8E7BDB" } } }
                MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; onClicked: bar.openMenu(4, btnLogo); onEntered: if (bar.menuUp && bar.menuIndex !== 4) bar.openMenu(4, btnLogo) }
            }
            BarBtn { id: btnApp; anchors.verticalCenter: parent.verticalCenter; label: bar.appName(bar.at); bold: true
                onClicked: bar.openMenu(0, btnApp); onEntered: if (bar.menuUp && bar.menuIndex !== 0) bar.openMenu(0, btnApp) }
            Rectangle { width: 1; height: 20; color: "#4DFFFFFF"; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
                id: menuRep
                model: bar.barMenus
                BarBtn {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    label: modelData.label
                    onClicked: bar.openMenu(modelData.id, this)
                    onEntered: if (bar.menuUp && bar.menuIndex !== modelData.id) bar.openMenu(modelData.id, this)
                }
            }
        }
    }

    Pill {
        id: rightPill
        anchors.right: parent.right
        anchors.rightMargin: 16
        width: rrow.implicitWidth + 12
        Row {
            id: rrow
            x: 6
            height: parent.height
            spacing: 2
            IconBtn { anchors.verticalCenter: parent.verticalCenter; name: Theme.dark ? "sun-w" : "moon-w"; onClicked: Theme.toggle() }
            Rectangle { width: 1; height: 20; color: "#4DFFFFFF"; anchors.verticalCenter: parent.verticalCenter }
            BarBtn {
                id: clockBtn
                anchors.verticalCenter: parent.verticalCenter
                label: Qt.formatDateTime(clock.date, "ddd d MMM") + "  " + Qt.formatDateTime(clock.date, "HH:mm")
                onClicked: Ui.togglePanel()
            }
            Item { visible: Notifs.count > 0; width: 20; height: 36; anchors.verticalCenter: parent.verticalCenter; Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#F6B8D4" } MouseArea { anchors.fill: parent; onClicked: Ui.togglePanel() } }
        }
    }

    ControlPanel { win: bar; target: rightPill }
}
