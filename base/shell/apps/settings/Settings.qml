import Quickshell
import Quickshell.Io
import QtQuick

// Smof Settings: a real window with a sidebar. Appearance, Display, Notifications, Network, Account, About.
FloatingWindow {
    id: win
    title: "Settings"
    readonly property real scrW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1366
    readonly property real scrH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 768
    // never larger than the screen minus the bar and the dock
    implicitWidth: Math.min(880, scrW - 24)
    implicitHeight: Math.min(600, scrH - 210)
    minimumSize: Qt.size(Math.min(560, implicitWidth), Math.min(420, implicitHeight))
    color: Theme.winbg
    visible: true
    property string page: Quickshell.env("SMOF_PAGE") || "appearance"

    readonly property var pages: [
        { id: "appearance", name: "Appearance", icon: "moon" },
        { id: "wallpaper", name: "Wallpaper", icon: "cloudsun" },
        { id: "desktop", name: "Desktop", icon: "dockfolder" },
        { id: "lockscreen", name: "Lock Screen", icon: "shield" },
        { id: "display", name: "Display", icon: "sun" },
        { id: "windows", name: "Windows", icon: "grid" },
        { id: "keyboard", name: "Keyboard", icon: "notes" },
        { id: "notifications", name: "Notifications", icon: "calendar" },
        { id: "network", name: "Network", icon: "sliders" },
        { id: "account", name: "Account", icon: "phone" },
        { id: "about", name: "About", icon: "notes" }
    ]

    // pictures the wallpaper can use, read from the Pictures and Downloads folders
    property var pics: []
    Process {
        id: picP
        command: ["python3", "-I", "-c", "import os,json\nr=[]\nfor d in ('Pictures','Downloads'):\n  p=os.path.join(os.path.expanduser('~'),d)\n  try:\n    for n in sorted(os.listdir(p)):\n      if n.lower().endswith(('.png','.jpg','.jpeg','.webp')) and os.path.getsize(os.path.join(p,n))<30000000: r.append(os.path.join(p,n))\n  except OSError: pass\nprint(json.dumps(r[:60]))"]
        stdout: StdioCollector { onStreamFinished: { try { win.pics = JSON.parse(text) } catch (e) {} } }
    }
    Process {
        id: cpP
        property string target: ""
        property string path: ""
        onExited: (code) => {
            if (code !== 0) return
            if (target === "desktop") { Look.wpImage = path; Look.wpMode = "image" }
            else { Look.lockImage = path; Look.lockMode = "image" }
        }
    }
    function useImage(src, target) {
        var ext = src.split(".").pop().toLowerCase()
        var dest = "/var/lib/smof/wp/" + target + "-" + Date.now() + "." + ext
        cpP.target = target; cpP.path = dest
        cpP.command = ["sh", "-c", "mkdir -p /var/lib/smof/wp && cp -f \"$0\" \"$1\" && chmod 644 \"$1\"", src, dest]
        cpP.running = true
    }

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
    onVisibleChanged: { if (!visible) Qt.quit(); else { infoP.running = true; netP.running = true; picP.running = true; dispP.running = true } }
    Timer { interval: 4000; repeat: true; running: win.visible && win.page === "network"; onTriggered: netP.running = true }

    FileView { id: uj; path: "/var/lib/smof/user.json"; blockLoading: true; printErrors: false }
    readonly property var user: { try { return JSON.parse(uj.text()) } catch (e) { return { name: Quickshell.env("USER"), user: Quickshell.env("USER") } } }

    // ---- screen resolution, refresh rate and scale (smof-display) ----
    property string dName: ""
    property var dModes: []
    property string dCurRes: ""
    property int dCurHz: 60
    property real dCurScale: 1
    property string dRes: ""
    property int dHz: 60
    property real dScale: 1
    property var dPrev: null
    property int dKeep: 0
    readonly property var dHzList: { for (var i = 0; i < dModes.length; i++) if (dModes[i].res === dRes) return dModes[i].hz; return [] }
    readonly property bool dChanged: dCurRes !== "" && (dRes !== dCurRes || dHz !== dCurHz || Math.abs(dScale - dCurScale) > 0.001)
    readonly property int dPw: Math.max(300, win.width - (win.width < 760 ? 190 : 230) - (win.width < 760 ? 48 : 64) - 40)
    Process {
        id: dispP
        command: ["/usr/local/bin/smof-display", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(text)[0]
                    win.dName = o.name
                    win.dModes = o.modes.filter(function (m) { return m.w >= 800 && m.h >= 600 })
                    win.dCurRes = o.current ? o.current.res : ""
                    win.dCurHz = o.current ? o.current.hz : 60
                    win.dCurScale = o.scale
                    win.dRes = win.dCurRes; win.dHz = win.dCurHz; win.dScale = win.dCurScale
                } catch (e) {}
            }
        }
    }
    Process { id: dispSet; onExited: dispRefresh.restart() }
    Timer { id: dispRefresh; interval: 1800; onTriggered: dispP.running = true }
    function setDisplay(res, hz, scale) {
        dispSet.command = ["/usr/local/bin/smof-display", "set", dName, res + "@" + hz, String(scale)]
        dispSet.running = true
    }
    function applyDisplay() {
        dPrev = { res: dCurRes, hz: dCurHz, scale: dCurScale }
        dKeep = 12
        setDisplay(dRes, dHz, dScale)
    }
    function keepDisplay() { dPrev = null; dKeep = 0 }
    function revertDisplay() {
        if (dPrev) setDisplay(dPrev.res, dPrev.hz, dPrev.scale)
        dPrev = null; dKeep = 0
    }
    Timer { interval: 1000; repeat: true; running: win.dKeep > 0; onTriggered: { win.dKeep -= 1; if (win.dKeep <= 0) win.revertDisplay() } }
    component Chip: Item {
        id: chip
        property string label: ""
        property bool on: false
        signal clicked()
        width: cht.implicitWidth + 30; height: 36
        Rectangle { anchors.fill: parent; radius: 18; color: chip.on ? Theme.acc : Theme.moonbg
            Rectangle { anchors.fill: parent; radius: 18; color: Theme.acc; opacity: chip.on ? 0 : (cma.containsMouse ? .14 : 0) } }
        T { id: cht; anchors.centerIn: parent; text: chip.label; w: 560; font.pixelSize: 15; color: chip.on ? Theme.onacc : Theme.ink }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
    }

    // ---- the folder tile in the dock (the dock reads ~/.config/smof-dock-stack.json) ----
    readonly property string homeDir: Quickshell.env("HOME")
    property string stackDir: homeDir + "/Downloads"
    FileView {
        path: win.homeDir + "/.config/smof-dock-stack.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { var o = JSON.parse(text()); if (o && o.dir) win.stackDir = o.dir } catch (e) {} }
    }
    Process { id: stackW }
    function setStack(path) {
        var p = path.trim()
        if (p.charAt(0) === "~") p = homeDir + p.slice(1)
        if (p.charAt(0) !== "/") return
        win.stackDir = p
        stackW.command = ["sh", "-c", "mkdir -p \"$HOME/.config\" && printf '{\"dir\": \"%s\"}' \"$0\" > \"$HOME/.config/smof-dock-stack.json\"", p]
        stackW.running = true
    }
    // ---- small building blocks ----
    // keyboard layouts
    Process { command: ["/usr/local/bin/smof-input", "layouts", "get"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { var o = JSON.parse(text); lpick.picked = o.layouts.map(function (x) { return { l: x.l, v: x.v } }); lpick.toggle = o.toggle } catch (e) {} } } }
    function saveLayouts() {
        var ls = lpick.picked.map(function (x) { return x.l }).join(",")
        var vs = lpick.picked.map(function (x) { return x.v }).join(",")
        Quickshell.execDetached(["/usr/local/bin/smof-input", "layouts", "set", ls, vs, lpick.toggle])
    }
    property bool natTouch: false
    property bool natMouse: false
    function setScroll(key, v) {
        if (key === "natural_scroll") natTouch = v; else natMouse = v
        Quickshell.execDetached(["/usr/local/bin/smof-input", "set", key, v ? "true" : "false"])
    }
    Process { command: ["/usr/local/bin/smof-input", "get"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { var o = JSON.parse(text); win.natTouch = o.natural_scroll; win.natMouse = o.mouse_natural_scroll } catch (e) {} } } }
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
        property bool stack: width < 480
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
    // a tile that shows one wallpaper choice
    component Swatch: Item {
        id: sw2
        property string kind: "dunes"      // dunes, gradient, image, same
        property var grad: null
        property string src: ""
        property bool picked: false
        property string label: ""
        signal clicked()
        width: 118; height: 92
        Rectangle { anchors.fill: parent; radius: 18; color: Theme.i12
            border.color: sw2.picked ? Theme.acc : "transparent"; border.width: 3 }
        Item {
            x: 5; y: 5; width: parent.width - 10; height: 58; clip: true
            Rectangle { anchors.fill: parent; radius: 14; color: "transparent" }
            Image { visible: sw2.kind === "dunes"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(300, 200); source: "file:///usr/share/smof/" + (Theme.dark ? "dark" : "light") + "_sky.jpg" }
            Rectangle { visible: sw2.kind === "gradient"; anchors.fill: parent; radius: 14
                gradient: Gradient { GradientStop { position: 0; color: sw2.grad ? (Theme.dark ? sw2.grad.d1 : sw2.grad.l1) : "#888" } GradientStop { position: 1; color: sw2.grad ? (Theme.dark ? sw2.grad.d2 : sw2.grad.l2) : "#444" } } }
            Image { visible: sw2.kind === "image"; anchors.fill: parent; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(240, 160); source: sw2.kind === "image" ? "file://" + sw2.src : "" }
            Rectangle { visible: sw2.kind === "same"; anchors.fill: parent; radius: 14; color: Theme.moonbg
                T { anchors.centerIn: parent; text: "="; font.pixelSize: 28; w: 600; color: Theme.acc } }
        }
        T { anchors.horizontalCenter: parent.horizontalCenter; y: 66; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: sw2.label; font.pixelSize: 13; color: sw2.picked ? Theme.acc : Theme.i62 }
        MouseArea { anchors.fill: parent; onClicked: sw2.clicked() }
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
                    readonly property bool cur: win.page === modelData.id
                    Rectangle { anchors.fill: parent; radius: 14; color: Theme.acc; opacity: cur ? 1 : (pma.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 120 } } }
                    Image { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; sourceSize: Qt.size(66, 66)
                        source: "file:///usr/share/smof/icons/" + modelData.icon + (cur ? (Theme.dark ? "" : "-d") : Theme.sfx) + ".svg" }
                    T { x: 48; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; w: cur ? 600 : 460; font.pixelSize: 17; color: cur ? Theme.onacc : Theme.ink }
                    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: win.page = modelData.id }
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

            T { text: { for (var i = 0; i < win.pages.length; i++) if (win.pages[i].id === win.page) return win.pages[i].name; return "" } w: 640; font.pixelSize: 30 }

            // Appearance extras are inside the Appearance block below

            // Wallpaper
            Column {
                visible: win.page === "wallpaper"
                width: parent.width; spacing: 14
                T { text: "Desktop"; font.pixelSize: 17; w: 600; color: Theme.acc }
                Flow {
                    width: parent.width; spacing: 10
                    Swatch { kind: "dunes"; label: "Dunes"; picked: Look.wpMode === "dunes"; onClicked: Look.wpMode = "dunes" }
                    Repeater { model: Look.gradients
                        Swatch { required property var modelData; kind: "gradient"; grad: modelData; label: modelData.name; picked: Look.wpMode === modelData.id; onClicked: Look.wpMode = modelData.id } }
                    Repeater { model: win.pics
                        Swatch { required property string modelData; kind: "image"; src: modelData; label: modelData.split("/").pop(); picked: Look.wpMode === "image" && Look.wpImage.indexOf("desktop-") > 0 && false; onClicked: win.useImage(modelData, "desktop") } }
                }
                Card {
                    Row2 { label: "Dim the wallpaper"; sub: "A soft dark veil, so icons and windows stand out"; last: true
                        Row { spacing: 12
                            Sld { from: 0; to: 0.5; value: Look.wpDim; onMoved: (v) => Look.wpDim = v }
                            Val { anchors.verticalCenter: parent.verticalCenter; text: Math.round(Look.wpDim * 200) + "%" } } }
                }
                T { id: lockHdr; text: "Lock screen"; font.pixelSize: 17; w: 600; color: Theme.acc }
                Flow {
                    width: parent.width; spacing: 10
                    Swatch { kind: "same"; label: "Same as desktop"; picked: Look.lockMode === "same"; onClicked: Look.lockMode = "same" }
                    Swatch { kind: "dunes"; label: "Dunes"; picked: Look.lockMode === "dunes"; onClicked: Look.lockMode = "dunes" }
                    Repeater { model: Look.gradients
                        Swatch { required property var modelData; kind: "gradient"; grad: modelData; label: modelData.name; picked: Look.lockMode === modelData.id; onClicked: Look.lockMode = modelData.id } }
                    Repeater { model: win.pics
                        Swatch { required property string modelData; kind: "image"; src: modelData; label: modelData.split("/").pop(); onClicked: win.useImage(modelData, "lock") } }
                }
                T { visible: win.pics.length === 0; text: "Put pictures in your Pictures or Downloads folder to use them here."; font.pixelSize: 14; color: Theme.i55; width: parent.width; wrapMode: Text.Wrap }
            }

            // Desktop
            Column {
                visible: win.page === "desktop"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "24 hour clock"; sub: "In the top bar"
                        Switch { on: Look.clock24; onToggled: (v) => Look.clock24 = v } }
                    Row2 { label: "Show the date"; sub: "Next to the time in the top bar"; last: true
                        Switch { on: Look.barDate; onToggled: (v) => Look.barDate = v } }
                }
                Card {
                    Row2 { label: "Dock size"; sub: "The biggest size of the icons in the dock"; last: true
                        Seg { options: ["Small", "Medium", "Large"]; index: Look.dockSize <= 50 ? 0 : (Look.dockSize <= 62 ? 1 : 2); onPicked: (i) => Look.dockSize = [48, 60, 72][i] } }
                }
                Card {
                    Row2 { stack: true; label: "Folder in the dock"; sub: "Shows its newest files next to the Trash. Pick one, or type any folder below."
                        Flow { width: win.dPw; spacing: 8
                            Repeater { model: ["Downloads", "Documents", "Desktop", "Pictures", "Music", "Videos"]
                                Chip { required property string modelData
                                    label: modelData; on: win.stackDir === win.homeDir + "/" + modelData
                                    onClicked: win.setStack(win.homeDir + "/" + modelData) } }
                            Chip { label: "Home"; on: win.stackDir === win.homeDir; onClicked: win.setStack(win.homeDir) } } }
                    Row2 { stack: true; label: "Any other folder"; sub: "Type a path and press Enter. In Files you can also right click a folder and choose Use as dock folder."; last: true
                        Rectangle { width: win.dPw; height: 44; radius: 22; color: Theme.moonbg
                            TextInput { id: stackIn; x: 18; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter; font.family: "Google Sans Flex"; font.pixelSize: 16; color: Theme.ink; clip: true; selectByMouse: true
                                text: win.stackDir
                                onAccepted: win.setStack(text) } } }
                }
            }

            // Lock screen
            Column {
                visible: win.page === "lockscreen"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Clock size"; sub: "The time on the lock screen"
                        Seg { options: ["Small", "Medium", "Large"]; index: Look.lockClock < 0.9 ? 0 : (Look.lockClock < 1.15 ? 1 : 2); onPicked: (i) => Look.lockClock = [0.75, 1.0, 1.3][i] } }
                    Row2 { label: "Clock position"; sub: "On the left or in the middle"
                        Seg { options: ["Left", "Center"]; index: Look.lockCenter ? 1 : 0; onPicked: (i) => Look.lockCenter = i === 1 } }
                    Row2 { label: "Show the date"; sub: "Under the time"; last: true
                        Switch { on: Look.lockDate; onToggled: (v) => Look.lockDate = v } }
                }
                T { text: "The wallpaper of the lock screen is chosen in Wallpaper."; font.pixelSize: 14; color: Theme.i55; width: parent.width; wrapMode: Text.Wrap }
            }

            // Appearance
            Column {
                visible: win.page === "appearance"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Theme"; sub: "Light or dark windows, panels and wallpaper"
                        Seg { options: ["Light", "Dark"]; index: Theme.dark ? 1 : 0; onPicked: (i) => Theme.apply(i === 1) } }
                    Row2 { label: "Accent colour"; sub: "Buttons, switches and highlights"
                        Row { spacing: 10
                            Repeater { model: Look.accents
                                Item { required property var modelData; required property int index; width: 34; height: 34
                                    Rectangle { anchors.fill: parent; radius: 17; color: Theme.dark ? modelData.d : modelData.l
                                        border.color: Look.accent === index ? Theme.ink : "transparent"; border.width: 3 }
                                    MouseArea { anchors.fill: parent; onClicked: Look.accent = index } } } } }
                    Row2 { label: "Calm motion"; sub: "Stops the slow sway of the wallpaper"; last: true
                        Switch { on: Ui.calm; onToggled: (v) => Ui.calm = v } }
                }
            }

            // Display
            Column {
                visible: win.page === "display"
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
                    Row2 { label: "Display"; sub: win.dCurRes !== "" ? win.dCurRes.replace("x", " x ") + " at " + win.dCurHz + " Hz, scale " + Math.round(win.dCurScale * 100) + "%" : ""; last: win.dModes.length === 0
                        Val { text: win.info.disp || "Built-in display" } }
                    Row2 { visible: win.dModes.length > 0; stack: true; label: "Resolution"; sub: "More pixels fit more on screen, smaller things"
                        Flow { width: win.dPw; spacing: 8
                            Repeater { model: win.dModes
                                Chip { required property var modelData
                                    label: modelData.res.replace("x", " x "); on: win.dRes === modelData.res
                                    onClicked: { win.dRes = modelData.res; if (modelData.hz.indexOf(win.dHz) < 0) win.dHz = modelData.hz[0] } } } } }
                    Row2 { visible: win.dHzList.length > 1; stack: true; label: "Refresh rate"
                        Flow { width: win.dPw; spacing: 8
                            Repeater { model: win.dHzList
                                Chip { required property int modelData
                                    label: modelData + " Hz"; on: win.dHz === modelData; onClicked: win.dHz = modelData } } } }
                    Row2 { visible: win.dModes.length > 0; stack: true; label: "Scale"
                        sub: win.dRes !== "" ? "Looks like " + Math.round(parseInt(win.dRes.split("x")[0]) / win.dScale) + " x " + Math.round(parseInt(win.dRes.split("x")[1]) / win.dScale) : ""
                        Flow { width: win.dPw; spacing: 8
                            Repeater { model: [1, 1.25, 1.5, 1.75, 2]
                                Chip { required property real modelData
                                    label: Math.round(modelData * 100) + "%"; on: Math.abs(win.dScale - modelData) < 0.001; onClicked: win.dScale = modelData } } } }
                    Row2 { visible: win.dModes.length > 0 && win.dKeep === 0; last: true; label: win.dChanged ? "Apply the new settings?" : "Screen is set"
                        sub: win.dChanged ? "You will have 12 seconds to keep them, or the old ones come back" : ""
                        Btn { label: "Apply"; visible: win.dChanged; onClicked: win.applyDisplay() } }
                    Row2 { visible: win.dKeep > 0; last: true; label: "Keep these display settings?"; sub: "Going back in " + win.dKeep + " s if you do nothing"
                        Row { spacing: 10
                            Btn { label: "Keep"; onClicked: win.keepDisplay() }
                            Btn { label: "Go back"; danger: true; onClicked: win.revertDisplay() } } }
                    Row2 { visible: win.dModes.length === 0; last: true; label: "Resolution and scale"; sub: "Not available on this screen"
                        Val { text: "" } }
                }
                Card {
                    Row2 { label: "Natural scrolling, touchpad"; sub: "Content follows your fingers"
                        Switch { on: win.natTouch; onToggled: (v) => win.setScroll("natural_scroll", v) } }
                    Row2 { label: "Natural scrolling, mouse"; sub: "Off: wheel down shows what is further down"; last: true
                        Switch { on: win.natMouse; onToggled: (v) => win.setScroll("mouse_natural_scroll", v) } }
                }
            }

            // Keyboard
            Column {
                visible: win.page === "keyboard"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "System language"; sub: "English for now, more languages are coming"; last: true; Val { text: "English" } }
                }
                Card {
                    Item {
                        width: parent.width; height: lpick.implicitHeight + 40
                        LayoutPicker { id: lpick; x: 20; y: 20; width: parent.width - 40; listHeight: 280; onChanged: win.saveLayouts() }
                    }
                }
            }

            // Windows
            Column {
                visible: win.page === "windows"
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
                    Row2 { label: "Hide bar and dock"; sub: "When a window comes over the bar or the dock they step aside, hold the cursor at the top or bottom edge to bring them back"; last: true
                        Switch { on: Ui.autohide; onToggled: (v) => Ui.autohide = v } }
                }
            }

            // Notifications
            Column {
                visible: win.page === "notifications"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Focus"; sub: "Hold back pop-ups, they still land in the panel"
                        Switch { on: Ui.dnd; onToggled: (v) => Ui.dnd = v } }
                    Row2 { label: "Saved notifications"; sub: NotifStore.count + (NotifStore.count === 1 ? " notification" : " notifications") + " in the panel"; last: true
                        Btn { label: "Clear all"; danger: true; onClicked: NotifStore.clearAll() } }
                }
                Card {
                    Row2 { label: "Sounds"; sub: "Short sounds for notifications, errors and the trash. Focus keeps them quiet"
                        Switch { on: Look.sounds; onToggled: (v) => Look.sounds = v } }
                    Row2 { label: "Volume"; last: true; opacity: Look.sounds ? 1 : .45
                        Row { spacing: 12
                            Sld { from: 0.1; to: 1.0; value: Look.soundVol; onMoved: (v) => { if (Look.sounds) Look.soundVol = v } }
                            Val { anchors.verticalCenter: parent.verticalCenter; text: Math.round(Look.soundVol * 100) + "%" } } }
                }
            }

            // Network
            Column {
                visible: win.page === "network"
                width: parent.width; spacing: 18
                Card {
                    Row2 { label: "Connection"; Val { text: win.netState } }
                    Row2 { label: "Address"; last: true; Val { text: win.netIp !== "" ? win.netIp : "None" } }
                }
            }

            // Account
            Column {
                visible: win.page === "account"
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
                visible: win.page === "about"
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

    // a picture dropped on the Wallpaper page becomes the wallpaper: above "Lock screen" for the desktop, below it for the lock screen
    DropArea {
        x: side.width; y: 0; width: fl.width; height: fl.height
        enabled: win.page === "wallpaper"
        onDropped: (d) => {
            if (!d.hasUrls) return
            var u = d.urls[0].toString()
            if (u.indexOf("file://") !== 0) return
            var p = decodeURIComponent(u.slice(7))
            if (!/\.(png|jpe?g|webp)$/i.test(p)) return
            var ly = lockHdr.mapToItem(win.contentItem, 0, 0).y
            d.acceptProposedAction()
            win.useImage(p, d.y > ly ? "lock" : "desktop")
        }
    }
}
