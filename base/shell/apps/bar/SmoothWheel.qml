import QtQuick

// mouse wheel and touchpad scrolling for the view this sits in (Flickable, ListView or GridView): smooth, vertical or horizontal.
// Put `SmoothWheel {}` inside the view.
WheelHandler {
    id: wh
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    property real step: 72                       // pixels for one notch of a mouse wheel
    property NumberAnimation ay: NumberAnimation { property: "contentY"; duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] }
    property NumberAnimation ax: NumberAnimation { property: "contentX"; duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] }
    onWheel: (ev) => {
        var f = wh.parent
        if (!f) return
        var horizontal = f.orientation !== undefined ? f.orientation === ListView.Horizontal : f.flickableDirection === Flickable.HorizontalFlick
        var a = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
        var d = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y * 0.5 : a / 120 * wh.step
        var anim = horizontal ? wh.ax : wh.ay
        var cur = horizontal ? f.contentX : f.contentY
        var lo = horizontal ? f.originX : f.originY
        var hi = lo + Math.max(0, horizontal ? f.contentWidth - f.width : f.contentHeight - f.height)
        var from = anim.running ? anim.to : cur
        var to = Math.max(lo, Math.min(hi, from - d))
        anim.stop(); anim.target = f; anim.from = cur; anim.to = to; anim.start()
    }
}
