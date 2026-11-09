import Quickshell
import Quickshell.Wayland
import QtQuick

// Beta Lab crash test: a picture of the screen is torn up more and more for a minute, then goes black. Esc stops it in the first 55 seconds.
ShellRoot {
    PanelWindow {
        id: w
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "smof-glitch"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "black"

        readonly property real total: Number(Quickshell.env("SMOF_GLITCH_SECONDS") || 60)
        readonly property string shot: Quickshell.env("SMOF_GLITCH_SHOT") || "/tmp/smof-glitch.png"
        property real t: 0
        property int tick: 0
        readonly property real k: Math.min(1, w.t / w.total)        // 0 at the start, 1 at the end
        readonly property int bands: 40
        readonly property bool dead: w.t >= w.total - 1.2

        Timer { interval: 40; repeat: true; running: true; onTriggered: { w.t += 0.04; w.tick++ } }

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: { if (w.t < w.total - 5) Quickshell.execDetached(["/usr/local/bin/smof-glitch", "abort"]) }

            Image { id: ref; visible: false; source: "file://" + w.shot; cache: false }
            // the picture of the screen in horizontal slices that jump sideways
            Repeater {
                model: w.bands
                Item {
                    id: band
                    required property int index
                    readonly property real bh: root.height / w.bands
                    property real off: 0
                    y: index * bh; width: root.width; height: bh
                    clip: true
                    visible: !w.dead
                    Connections {
                        target: w
                        function onTickChanged() {
                            var p = 0.02 + 0.55 * w.k * w.k
                            if (Math.random() < p) band.off = (Math.random() - 0.5) * root.width * (0.04 + 0.5 * w.k)
                            else if (Math.random() < 0.25) band.off = 0
                        }
                    }
                    Image {
                        x: band.off; y: 0; width: root.width; height: band.bh
                        source: ref.source; cache: false; fillMode: Image.Stretch
                        sourceClipRect: ref.implicitWidth > 0 ? Qt.rect(0, band.index * (ref.implicitHeight / w.bands), ref.implicitWidth, ref.implicitHeight / w.bands) : Qt.rect(0, 0, 0, 0)
                    }
                }
            }
            // blocks of colour that flash on, more and more of them
            Repeater {
                model: 70
                Rectangle {
                    id: blk
                    visible: !w.dead && Math.random() < w.k * 0.9 && w.k > 0.2
                    property int seed: 0
                    x: Math.random() * root.width; y: Math.random() * root.height
                    width: 8 + Math.random() * root.width * 0.25 * w.k; height: 4 + Math.random() * 40 * (0.3 + w.k)
                    color: ["#ff00ff", "#00ffff", "#00ff40", "#ffffff", "#ff0030", "#000000"][Math.floor(Math.random() * 6)]
                    opacity: 0.4 + 0.6 * Math.random()
                    Connections { target: w; function onTickChanged() { blk.seed++; if (Math.random() < 0.5) { blk.x = Math.random() * root.width; blk.y = Math.random() * root.height } } }
                }
            }
            // numbers pouring out of memory in the second half
            Column {
                visible: w.k > 0.5 && !w.dead
                x: 24; y: 24; spacing: 2
                opacity: Math.min(1, (w.k - 0.5) * 3)
                Repeater {
                    model: 16
                    Text {
                        id: hx
                        property string s: ""
                        text: hx.s
                        color: "#7CFF7C"; font.family: "monospace"; font.pixelSize: 15
                        Connections {
                            target: w
                            function onTickChanged() {
                                var o = "0x"
                                for (var i = 0; i < 6 + Math.floor(w.k * 20); i++) o += "0123456789ABCDEF".charAt(Math.floor(Math.random() * 16))
                                hx.s = o + (w.k > 0.8 ? "  CORRUPT" : "")
                            }
                        }
                    }
                }
            }
            // a scan line that sweeps the screen
            Rectangle { visible: !w.dead; width: root.width; height: 3 + 10 * w.k; y: (w.t * 220) % root.height; color: "#33FFFFFF" }
            // whole screen flicker
            Rectangle { anchors.fill: parent; color: "white"; visible: !w.dead; opacity: Math.random() < 0.1 * w.k * w.k ? 0.35 : 0 }
            // the end
            Rectangle { anchors.fill: parent; color: "black"; visible: w.dead }
            Text { visible: w.dead && w.t < w.total + 5; anchors.left: parent.left; anchors.leftMargin: 24; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
                text: "Kernel panic - not syncing"; color: "#CCCCCC"; font.family: "monospace"; font.pixelSize: 16 }
        }
    }
}
