import QtQuick

// smooth spinner: a thin ring with a comet arc, drawn once and turned by the GPU
Item {
    id: sp
    property bool active: true
    width: 52
    height: 52
    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var c = getContext("2d")
            c.reset()
            c.lineCap = "round"
            var cx = width / 2, cy = height / 2
            var lw = Math.max(2.5, width * 0.065)
            var r = width / 2 - lw
            c.lineWidth = lw
            c.strokeStyle = "rgba(255,255,255,0.22)"
            c.beginPath(); c.arc(cx, cy, r, 0, 2 * Math.PI); c.stroke()
            var N = 72, span = 1.55 * Math.PI
            for (var i = 0; i < N; i++) {
                var t = i / N
                var a0 = -Math.PI / 2 + t * span
                var a1 = a0 + span / N + 0.03
                c.strokeStyle = "rgba(255,255,255," + Math.pow(t, 1.4).toFixed(3) + ")"
                c.beginPath(); c.arc(cx, cy, r, a0, a1); c.stroke()
            }
        }
        RotationAnimator on rotation { from: 0; to: 360; duration: 950; loops: Animation.Infinite; running: sp.active && sp.visible }
    }
}
