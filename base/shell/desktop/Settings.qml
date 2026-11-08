import Quickshell
import Quickshell.Io
import QtQuick

// Smof Settings: a real window with a sidebar. Appearance, Display, Notifications, Network, Account, About.
FloatingWindow {
    id: win
    title: "Settings"
    implicitWidth: 880
    implicitHeight: 600
    minimumSize: Qt.size(560, 420)
    color: Theme.winbg
    visible: Ui.settingsOpen

    readonly property var pages: [
        { id: "appearance", name: "Appearance", icon: "moon" },
        { id: "display", name: "Display", icon: "sun" },
        { id: "windows", name: "Windows", icon: "grid" },
        { id: "notifications", name: "Notifications", icon: "calendar" },
        { id: "network", name: "Network", icon: "cloudsun" },
        { id: "account", name: "Account", icon: "phone" },
        { id: "about", name: "About", icon: "shield" }
    ]

    // ---- system info read from the machine ----
    property var info: ({})
    property string netIp: ""
    property string netState: "…"
    Process {
        id: infoP
        command: ["sh", "-c", ". /etc/os-release; echo os=$PRETTY_NAME; echo kernel=$(uname -r); echo host=$(cat /etc/hostname); echo cpu=$(nproc) cores; echo mem=$(free -h | awk '/Mem/{print $3\" of \"$2}'); echo disk=$(df -h / | awk 'NR==2{print $3\" of \"$2}'); echo up=$(uptime -p | sed 's/^up //'); echo disp=$(wlr-randr 2>/dev/null | awk '/current/{print $1; exit}')"]
        stdout: StdioCollector {
            onStreamFinished: {
                var o = {}
                text.split("\n").forEach(function (l) { var i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1) })
                win.info = o
            }
        }
    }
    Process {
        id: netP
        command: ["sh", "-c", "s=$(cat /sys/class/net/e*/operstate /sys/class/net/w*/operstate 2>/dev/null | head -1); echo state=$s; echo ip=$(ip -4 -brief addr show scope global 2>/dev/null | awk 'NR==1{print $1\" \"$3}')"]
        stdout: StdioCollector {
            onStreamFinished: {
                text.split("\n").forEach(function (l) {
                    if (l.indexOf("state=") === 0) win.netState = l.slice(6).trim() === "up" ? "Connected" : "Off"
                    if (l.indexOf("ip=") === 0) win.netIp = l.slice(3).trim()
                })
            }
        }
    }
    onVisibleChanged: { if (!visible) Ui.settingsOpen = false; else { infoP.running = true; netP.running = true } }
    Timer { interval: 4000; repeat: true; running: win.visible && Ui.settingsPage === "network"; onTriggered: netP.running = true }

    FileView { id: uj; path: "/var/lib/smof/user.json"; blockLoading: true; printErrors: false }
    readonly property var user: { try { return JSON.parse(uj.text()) } catch (e) { return { name: Quickshell.env("USER"), user: Quickshell.env("USER") } } }

    // ---- small building blocks ----
    component Card: Rectangle {
        default property alias content: col.data
        width: parent ? parent.width : 400
        height: col.implicitHeight
        radius: 20
        color: Theme.cardbg
        Behavior on color { ColorAnimation { duration: 300 } }
        Column { id: col; width: parent.width }
    }
    component Row2: Item {
        id: r
        property string label: ""
        property string sub: ""
        property bool last: false
        default property alias ctl: slot.data
        // a narrow card puts the control under the text instead of squeezing the text to nothing
        readonly property bool stack: width < 480
        width: parent ? parent.width : 400
        height: stack ? lt.implicitHeight + slot.height + 40 : Math.max(58, lt.implicitHeight + 24)
        Column {
            id: lt
            x: 20
            y: r.stack ? 14 : (r.height - lt.implicitHeight) / 2
            width: r.stack ? r.width - 40 : Math.max(150, r.width - 40 - slot.width - 16)
            spacing: 2
            T { text: r.label; w: 520; font.pixelSize: 17; elide: Text.ElideRight; width: parent.width }
            T { visible: r.sub !== ""; text: r.sub; font.pixelSize: 14; color: Theme.i55; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; width: parent.width }
        }
        Item {
            id: slot
            x: r.stack ? 20 : r.width - 20 - width
            y: r.stack ? lt.y + lt.implicitHeight + 12 : (r.height - height) / 2
            width: childrenRect.width; height: childrenRect.height
        }
        Rectangle { visible: !r.last; anchors.bottom: parent.bottom; x: 20; width: parent.width - 20; height: 1; color: Theme.i12 }
    }
    component Switch: Item {
        id: sw
        property bool on: false
        signal toggled(bool v)
        width: 54; height: 32
        Rectangle { anchors.fill: parent; radius: 16; color: sw.on ? Theme.acc : Theme.i12; Behavior on color { ColorAnimation { duration: 180 } } }
        Rectangle { width: 26; height: 26; radius: 13; y: 3; x: sw.on ? 25 : 3; color: sw.on ? Theme.onacc : (Theme.dark ? "#C9C0E6" : "#FFFFFF"); Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
        MouseArea { anchors.fill: parent; onClicked: sw.toggled(!sw.on) }
    }
    component Seg: Item {
        id: sg
        property var options: []
        property int index: 0
        signal picked(int i)
        width: options.length * 100 + 6; height: 38
        Rectangle { anchors.fill: parent; radius: 19; color: Theme.i12 }
        Rectangle { x: 3 + sg.index * 100; y: 3; width: 100; height: 32; radius: 16; color: Theme.acc; Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        Row {
            x: 3; y: 3
            Repeater {
                model: sg.options
                Item {
                    required property string modelData
                    required property int index
                    width: 100; height: 32
                    T { anchors.centerIn: parent; text: modelData; w: 560; font.pixelSize: 15; color: sg.index === index ? Theme.onacc : Theme.ink }
                    MouseArea { anchors.fill: parent; onClicked: sg.picked(index) }
                }
            }
        }
    }
    component Sld: Item {
        id: sl
        property real value: 0.5
        property real from: 0
        property real to: 1
        signal moved(real v)
        width: 220; height: 32
        readonly property real frac: (value - from) / (to - from)
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 8; radius: 4; color: Theme.i12 }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Math.max(8, parent.width * sl.frac); height: 8; radius: 4; color: Theme.acc }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; x: (parent.width - 8) * sl.frac; width: 8; height: 24; radius: 4; color: Theme.acc }
        MouseArea {
            anchors.fill: parent
            function set(mx) { sl.moved(sl.from + Math.max(0, Math.min(1, mx / width)) * (sl.to - sl.from)) }
            onPressed: (m) => set(m.x)
            onPositionChanged: (m) => { if (pressed) set(m.x) }
        }
    }
    component Btn: Item {
        id: bt
        property string label: ""
        property bool danger: false
        signal clicked()
        width: btt.implicitWidth + 36; height: 38
        Rectangle { anchors.fill: parent; radius: 19; color: bt.danger ? Theme.errbg : Theme.moonbg; Rectangle { anchors.fill: parent; radius: 19; color: bt.danger ? Theme.errfg : Theme.acc; opacity: bma.pressed ? .22 : (bma.containsMouse ? .12 : 0) } }
        T { id: btt; anchors.centerIn: parent; text: bt.label; w: 560; font.pixelSize: 15; color: bt.danger ? Theme.errfg : Theme.acc }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; onClicked: bt.clicked() }
    }
    component Val: T {
        font.pixelSize: 16; color: Theme.i62
    }

    // ---- layout ----
    Rectangle {
        id: side
        width: win.width < 760 ? 190 : 230; height: parent.height
        color: Theme.sidebg
        Behavior on color { ColorAnimation { duration: 300 } }
        Column {
            x: 12; y: 16; width: parent.width - 24; spacing: 4
            Repeater {
                model: win.pages
                Item {
                    required property var modelData
                    width: parent.width; height: 44
                    readonly property bool cur: Ui.settingsPage === modelData.id
                    Rectangle { anchors.fill: parent; radius: 14; color: Theme.acc; opacity: cur ? 1 : (pma.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 120 } } }
                    Image { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; sourceSize: Qt.size(66, 66)
                        source: "file:///usr/share/smof/icons/" + modelData.icon + (cur ? (Theme.dark ? "" : "-d") : Theme.sfx) + ".svg" }
                    T { x: 48; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; w: cur ? 600 : 460; font.pixelSize: 17; color: cur ? Theme.onacc : Theme.ink }
                    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: Ui.settingsPage = modelData.id }
                }
            }
        }
    }

    Flickable {
        id: fl
        x: side.width; width: parent.width - side.width; height: parent.height
        contentHeight: pageCol.implicitHeight + 64
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: pageCol
            x: win.width < 760 ? 24 : 32; y: 28
            width: fl.width - (win.width < 760 ? 48 : 64)
            spacing: 18

            T { text: { for (var i = 0; i < win.pages.length; i++) if (win.pages[i].id === Ui.settingsPage) return win.pages[i].name; return "" } w: 640; font.pixelSize: 30 }

            // Appearance
            Column {
                visible: Ui.settingsPage === "appearance"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Theme"; sub: "Light or dark windows, panels and wallpaper"
                        Seg { options: ["Light", "Dark"]; index: Theme.dark ? 1 : 0; onPicked: (i) => Theme.apply(i === 1) } }
                    Row2 { label: "Calm motion"; sub: "Stops the slow sway of the wallpaper"; last: true
                        Switch { on: Ui.calm; onToggled: (v) => Ui.calm = v } }
                }
            }

            // Display
            Column {
                visible: Ui.settingsPage === "display"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Brightness"; sub: "Dims the whole screen"
                        Row { spacing: 12
                            Sld { from: 0.3; to: 1.0; value: Ui.brightness; onMoved: (v) => Ui.brightness = v }
                            Val { anchors.verticalCenter: parent.verticalCenter; text: Math.round(Ui.brightness * 100) + "%" } } }
                    Row2 { label: "Low power"; sub: "Saves energy by easing animations"; last: true
                        Switch { on: Ui.lowpower; onToggled: (v) => Ui.lowpower = v } }
                }
                Card {
                    Row2 { label: "Display"; last: true; Val { text: win.info.disp || "Built-in display" } }
                }
            }

            // Windows
            Column {
                visible: Ui.settingsPage === "windows"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Window zones"; sub: "A second window moves the first to the left half and takes the right half. More windows share the screen in zones"; last: true
                        Switch { on: Ui.tiling; onToggled: (v) => Ui.tiling = v } }
                }
                Card {
                    opacity: Ui.tiling ? 1 : .45
                    Row2 { label: "Gap between windows"; sub: "Space between zones"
                        Row { spacing: 12
                            Sld { from: 0; to: 30; value: Ui.tileGap; onMoved: (v) => { if (Ui.tiling) Ui.tileGap = Math.round(v) } }
                            Val { anchors.verticalCenter: parent.verticalCenter; text: Ui.tileGap + " px" } } }
                    Row2 { label: "Screen edge margin"; sub: "Space between zones and the screen edge"
                        Row { spacing: 12
                            Sld { from: 0; to: 40; value: Ui.tileSide; onMoved: (v) => { if (Ui.tiling) Ui.tileSide = Math.round(v) } }
                            Val { anchors.verticalCenter: parent.verticalCenter; text: Ui.tileSide + " px" } } }
                    Row2 { label: "Keep clear of bar and dock"; sub: "Zones leave room at the top and the bottom. Off: zones use the whole screen"; last: true
                        Switch { on: Ui.tileClear; onToggled: (v) => { if (Ui.tiling) Ui.tileClear = v } } }
                }
                Card {
                    Row2 { label: "Hide bar and dock"; sub: "When a window fills the screen they step aside, move the cursor to the top or bottom edge to bring them back"; last: true
                        Switch { on: Ui.autohide; onToggled: (v) => Ui.autohide = v } }
                }
            }

            // Notifications
            Column {
                visible: Ui.settingsPage === "notifications"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Focus"; sub: "Hold back pop-ups, they still land in the panel"
                        Switch { on: Ui.dnd; onToggled: (v) => Ui.dnd = v } }
                    Row2 { label: "Saved notifications"; sub: Notifs.count + (Notifs.count === 1 ? " notification" : " notifications") + " in the panel"; last: true
                        Btn { label: "Clear all"; danger: true; onClicked: Notifs.clearAll() } }
                }
            }

            // Network
            Column {
                visible: Ui.settingsPage === "network"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Connection"; Val { text: win.netState } }
                    Row2 { label: "Address"; last: true; Val { text: win.netIp !== "" ? win.netIp : "None" } }
                }
            }

            // Account
            Column {
                visible: Ui.settingsPage === "account"
                width: parent.width; spacing: 18
                Card {
                    Item {
                        width: parent.width; height: 104
                        Rectangle {
                            x: 20; anchors.verticalCenter: parent.verticalCenter; width: 64; height: 64; radius: 32
                            gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#F6B8D4" } GradientStop { position: 1; color: "#8E7BDB" } }
                            T { anchors.centerIn: parent; text: (win.user.name || "?").charAt(0).toUpperCase(); w: 560; font.pixelSize: 30; color: "#FFFFFF" }
                        }
                        Column { x: 100; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            T { text: win.user.name || ""; w: 600; font.pixelSize: 22 }
                            T { text: win.user.user || ""; font.pixelSize: 15; color: Theme.i55 } }
                    }
                }
                Card {
                    Row2 { label: "PIN"; sub: "Changing it from here comes later. For now: passwd in the terminal"; last: true; Val { text: "Protected" } }
                }
            }

            // About
            Column {
                visible: Ui.settingsPage === "about"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "System"; Val { text: win.info.os || "" } }
                    Row2 { label: "Device name"; Val { text: win.info.host || "" } }
                    Row2 { label: "Kernel"; Val { text: win.info.kernel || "" } }
                    Row2 { label: "Processor"; Val { text: win.info.cpu || "" } }
                    Row2 { label: "Memory"; Val { text: win.info.mem || "" } }
                    Row2 { label: "Storage"; Val { text: win.info.disk || "" } }
                    Row2 { label: "Running for"; last: true; Val { text: win.info.up || "" } }
                }
            }
        }
    }
}
