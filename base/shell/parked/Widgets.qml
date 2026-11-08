import QtQuick

// right column of the lock screen: weather, next event, music, battery, focus, timer
Item {
    id: ws
    property int step: 0
    property bool gone: false
    function vis(n) { return !gone && step >= n }
    width: 612
    height: 548

    // weather
    WCard { x: 0; y: 0; width: 300; height: 190; on: ws.vis(3)
        T { x: 20; y: 20; text: "Today"; w: 470; font.pixelSize: 18; color: Theme.i55 }
        Ico { x: 252; y: 20; width: 28; height: 28; name: "cloudsun" }
        T { x: 20; y: 58; text: "-4°"; w: 470; font.pixelSize: 52 }
        T { x: 20; y: 125; text: "Partly cloudy"; w: 470; font.pixelSize: 18; color: Theme.i8 }
        T { x: 20; y: 150; text: "H -1°  L -9°"; font.pixelSize: 16; color: Theme.i55 }
    }
    // next event
    WCard { x: 312; y: 0; width: 300; height: 190; on: ws.vis(4)
        T { x: 20; y: 20; text: "Next up"; w: 470; font.pixelSize: 18; color: Theme.i55 }
        Ico { x: 252; y: 20; width: 28; height: 28; name: "calendar" }
        Rectangle { x: 20; y: 62; width: 6; height: 72; radius: 3; color: Theme.acc2 }
        T { x: 40; y: 62; text: "Design review"; w: 560; font.pixelSize: 22 }
        T { x: 40; y: 92; text: "14:30 – 15:15"; font.pixelSize: 16; color: Theme.i6 }
        T { x: 40; y: 114; text: "Room 4"; font.pixelSize: 16; color: Theme.i6 }
    }
    // music
    WCard { x: 0; y: 202; width: 612; height: 150; on: ws.vis(5)
        Rectangle { x: 20; y: 20; width: 110; height: 110; radius: 22
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#F6B8D4" } GradientStop { position: 1; color: "#8E7BDB" } }
            Rectangle { x: 62; y: 24; width: 34; height: 34; radius: 17; color: "#E6FFE9CC" } }
        T { x: 150; y: 21; text: "Dusty Hills"; w: 560; font.pixelSize: 26 }
        T { x: 150; y: 55; text: "Mellow Waves"; font.pixelSize: 18; color: Theme.i55 }
        Rectangle { x: 150; y: 80; width: 440; height: 6; radius: 3; color: Theme.i12
            Rectangle { width: 170; height: 6; radius: 3; color: Theme.acc } }
        Ico { x: 302; y: 97; width: 22; height: 22; name: "skipback" }
        Rectangle { x: 350; y: 89; width: 40; height: 40; radius: 20; color: Theme.i9
            Ico { x: 12; y: 11; width: 18; height: 18; name: "play" } }
        Ico { x: 416; y: 97; width: 22; height: 22; name: "skipfwd" }
    }
    // battery
    WCard { x: 0; y: 364; width: 196; height: 184; on: ws.vis(6)
        T { x: 20; y: 20; text: "Battery"; w: 470; font.pixelSize: 18; color: Theme.i55 }
        Canvas { id: ring; x: 20; y: 80; width: 84; height: 84
            property real v: ws.vis(6) ? 0.82 : 0
            Behavior on v { NumberAnimation { duration: 1000; easing.type: Easing.OutCubic } }
            onVChanged: requestPaint()
            Connections { target: Theme; function onDarkChanged() { ring.requestPaint() } }
            onPaint: {
                var c = getContext("2d"); c.reset(); c.lineWidth = 8; c.lineCap = "round"
                c.strokeStyle = Theme.dark ? "rgba(244,240,255,.16)" : "rgba(23,18,41,.12)"; c.beginPath(); c.arc(42, 42, 34, 0, 2 * Math.PI); c.stroke()
                if (v > 0.001) { c.strokeStyle = String(Theme.acc); c.beginPath(); c.arc(42, 42, 34, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * v); c.stroke() }
            }
            T { anchors.centerIn: parent; text: "82%"; w: 560; font.pixelSize: 22 }
        }
    }
    // focus
    WCard { x: 208; y: 364; width: 196; height: 184; on: ws.vis(7)
        T { x: 20; y: 20; text: "Focus"; w: 470; font.pixelSize: 18; color: Theme.i55 }
        Rectangle { x: 20; y: 57; width: 48; height: 48; radius: 24; color: Theme.moonbg
            Ico { anchors.centerIn: parent; width: 26; height: 26; name: "moon" } }
        T { x: 20; y: 119; text: "Do not disturb"; w: 560; font.pixelSize: 19 }
        T { x: 20; y: 144; text: "Until 18:00"; font.pixelSize: 16; color: Theme.i55 }
    }
    // timer
    WCard { x: 416; y: 364; width: 196; height: 184; on: ws.vis(8)
        T { x: 20; y: 20; text: "Timer"; w: 470; font.pixelSize: 18; color: Theme.i55 }
        T { x: 20; y: 92; text: "25:00"; w: 560; font.pixelSize: 40 }
        T { x: 20; y: 144; text: "Tap to start"; font.pixelSize: 16; color: Theme.i55 }
    }
}
