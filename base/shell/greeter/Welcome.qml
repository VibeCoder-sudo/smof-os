import Quickshell
import Quickshell.Io
import QtQuick

// First screen of the live image: try Smof, or install it onto the disk. Install lists the free space on the disks, unpacks the system
// with smof-install (root helper, one JSON line per step) and offers a restart.
Item {
    id: w
    signal tryIt()
    property string mode: "choose"          // choose, disks, working, done, error
    property var disks: []
    property int pick: -1                   // index of the chosen disk
    property real pct: 0
    property string stepText: ""
    property string errText: ""
    readonly property real gb: 1073741824
    readonly property int needGb: 12
    focus: true

    function freeOf(d) { var t = 0; for (var i = 0; i < d.free.length; i++) t += d.free[i].size; return t }
    function usable(d) { for (var i = 0; i < d.free.length; i++) if (d.free[i].size >= w.needGb * w.gb) return true; return false }
    function fmt(b) { return b >= w.gb ? (b / w.gb).toFixed(b >= 10 * w.gb ? 0 : 1) + " GB" : Math.round(b / 1048576) + " MB" }
    function nice(d) { return (d.model && d.model !== "" ? d.model : d.path) }

    Process {
        id: listP
        command: ["/usr/bin/sudo", "-n", "/usr/local/sbin/smof-install", "list"]
        stdout: StdioCollector { onStreamFinished: { try { w.disks = JSON.parse(text) } catch (e) { w.disks = [] }
            w.pick = -1; for (var i = 0; i < w.disks.length; i++) if (w.usable(w.disks[i])) { w.pick = i; break }
            w.mode = "disks" } }
    }
    Process {
        id: runP
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var o = JSON.parse(line)
                    if (o.step === "error") { w.errText = o.text; w.mode = "error" }
                    else { w.pct = o.pct; w.stepText = o.text; if (o.step === "done") w.mode = "done" }
                } catch (e) {}
            }
        }
        onExited: (code) => { if (code !== 0 && w.mode === "working") { if (w.errText === "") w.errText = "The installer stopped"; w.mode = "error" } }
    }
    function startInstall() {
        var d = w.disks[w.pick]
        w.pct = 0; w.stepText = "Starting"; w.errText = ""; w.mode = "working"
        runP.command = ["/usr/bin/sudo", "-n", "/usr/local/sbin/smof-install", "run", "--disk", d.path, "--min-gb", String(w.needGb)]
        runP.running = true
    }
    Process { id: rebootP; command: ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "reboot"] }

    Rectangle { anchors.fill: parent; color: "#0f0d16" }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 760)
        spacing: 26

        T { visible: w.mode === "choose"; anchors.horizontalCenter: parent.horizontalCenter; text: "smof"; font.pixelSize: 96; w: 420; color: "#FFFFFF" }
        T { visible: w.mode === "choose"; anchors.horizontalCenter: parent.horizontalCenter; text: "A friendly Arch Linux desktop"; font.pixelSize: 22; color: "#B8FFFFFF" }
        Row {
            visible: w.mode === "choose"; anchors.horizontalCenter: parent.horizontalCenter; spacing: 18; topPadding: 20
            Rectangle { width: 300; height: 74; radius: 37; color: Theme.acc
                T { anchors.centerIn: parent; text: "Try Smof"; font.pixelSize: 24; w: 620; color: Theme.onacc }
                MouseArea { anchors.fill: parent; onClicked: w.tryIt() } }
            Rectangle { width: 300; height: 74; radius: 37; color: "#26FFFFFF"; border.color: "#44FFFFFF"
                T { anchors.centerIn: parent; text: "Install Smof"; font.pixelSize: 24; w: 620; color: "#FFFFFF" }
                MouseArea { anchors.fill: parent; onClicked: { w.mode = "disks"; w.disks = []; listP.running = true } } }
        }
        T { visible: w.mode === "choose"; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: "Try Smof runs from memory and changes nothing on your computer. Install Smof puts it on a disk next to what is already there."; font.pixelSize: 15; color: "#8CFFFFFF" }

        T { visible: w.mode === "disks"; text: "Where should Smof go?"; font.pixelSize: 40; w: 600; color: "#FFFFFF" }
        T { visible: w.mode === "disks"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 16; color: "#B8FFFFFF"
            text: w.disks.length === 0 ? "Looking at the disks…" : "Smof is installed into free space, nothing that is already there is deleted or formatted. It needs at least " + w.needGb + " GB of free space. If there is none, shrink a partition in Windows first." }
        Column {
            visible: w.mode === "disks"; width: parent.width; spacing: 10
            Repeater {
                model: w.disks
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool ok: w.usable(modelData)
                    width: parent.width; height: 78; radius: 22
                    color: w.pick === index ? "#33FFFFFF" : "#1AFFFFFF"; border.color: w.pick === index ? Theme.acc : "#22FFFFFF"; border.width: w.pick === index ? 2 : 1
                    opacity: ok ? 1 : .45
                    T { x: 22; y: 14; text: w.nice(modelData) + "  " + w.fmt(modelData.size); font.pixelSize: 19; w: 600; color: "#FFFFFF" }
                    T { x: 22; y: 44; text: ok ? w.fmt(w.freeOf(modelData)) + " free space, Smof takes the largest piece" : "Not enough free space (" + w.fmt(w.freeOf(modelData)) + ")"; font.pixelSize: 15; color: "#B8FFFFFF" }
                    MouseArea { anchors.fill: parent; enabled: ok; onClicked: w.pick = index }
                }
            }
        }
        Row {
            visible: w.mode === "disks"; spacing: 14
            Rectangle { width: 170; height: 58; radius: 29; color: "#26FFFFFF"; T { anchors.centerIn: parent; text: "Back"; font.pixelSize: 19; w: 560; color: "#FFFFFF" }
                MouseArea { anchors.fill: parent; onClicked: w.mode = "choose" } }
            Rectangle { width: 240; height: 58; radius: 29; color: w.pick >= 0 ? Theme.acc : "#26FFFFFF"; opacity: w.pick >= 0 ? 1 : .5
                T { anchors.centerIn: parent; text: "Install"; font.pixelSize: 19; w: 620; color: w.pick >= 0 ? Theme.onacc : "#FFFFFF" }
                MouseArea { anchors.fill: parent; enabled: w.pick >= 0; onClicked: w.startInstall() } }
        }

        T { visible: w.mode === "working"; text: "Installing Smof"; font.pixelSize: 40; w: 600; color: "#FFFFFF" }
        Rectangle { visible: w.mode === "working"; width: parent.width; height: 10; radius: 5; color: "#26FFFFFF"
            Rectangle { width: parent.width * w.pct / 100; height: parent.height; radius: 5; color: Theme.acc; Behavior on width { NumberAnimation { duration: 300 } } } }
        T { visible: w.mode === "working"; text: w.stepText; font.pixelSize: 17; color: "#B8FFFFFF" }
        T { visible: w.mode === "working"; text: "Please do not turn the computer off."; font.pixelSize: 14; color: "#8CFFFFFF" }

        T { visible: w.mode === "done"; text: "Smof is installed"; font.pixelSize: 44; w: 600; color: "#FFFFFF" }
        T { visible: w.mode === "done"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 17; color: "#B8FFFFFF"
            text: "Restart now. In the boot menu choose Smof, Windows is still there as well. Remove the USB stick first if you used one." }
        Rectangle { visible: w.mode === "done"; width: 260; height: 62; radius: 31; color: Theme.acc
            T { anchors.centerIn: parent; text: "Restart"; font.pixelSize: 21; w: 620; color: Theme.onacc }
            MouseArea { anchors.fill: parent; onClicked: rebootP.running = true } }

        T { visible: w.mode === "error"; text: "That did not work"; font.pixelSize: 40; w: 600; color: "#FFFFFF" }
        T { visible: w.mode === "error"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 16; color: "#FFB59E"; text: w.errText }
        Row {
            visible: w.mode === "error"; spacing: 14
            Rectangle { width: 200; height: 58; radius: 29; color: "#26FFFFFF"; T { anchors.centerIn: parent; text: "Back"; font.pixelSize: 19; w: 560; color: "#FFFFFF" }
                MouseArea { anchors.fill: parent; onClicked: w.mode = "choose" } }
            Rectangle { width: 200; height: 58; radius: 29; color: Theme.acc; T { anchors.centerIn: parent; text: "Try Smof"; font.pixelSize: 19; w: 620; color: Theme.onacc }
                MouseArea { anchors.fill: parent; onClicked: w.tryIt() } }
        }
    }
}
