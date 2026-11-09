import Quickshell
import Quickshell.Io
import QtQuick

// Keyboard layouts: the ones in use as chips (first one is the main one), a shortcut to switch, and a search through every layout there is.
// `picked` is a list of { l: "us", v: "" }. Used by Settings and by the first run setup.
Item {
    id: lp
    property var picked: [{ l: "us", v: "" }]
    property string toggle: "ctrl_space"
    property int listHeight: 260
    signal changed()
    width: parent ? parent.width : 400
    implicitHeight: col.implicitHeight

    property var all: []
    property var toggles: []
    property string open: ""                  // layout whose variants are showing
    property string query: ""
    readonly property var byCode: { var m = {}; for (var i = 0; i < all.length; i++) m[all[i].c] = all[i]; return m }
    function nameOf(x) {
        var e = byCode[x.l]
        if (!e) return x.l
        if (x.v !== "") for (var i = 0; i < e.v.length; i++) if (e.v[i].c === x.v) return e.v[i].n
        return e.n
    }
    readonly property var shown: {
        var q = query.trim().toLowerCase(), out = []
        for (var i = 0; i < all.length; i++) {
            var e = all[i]
            if (q === "" || e.n.toLowerCase().indexOf(q) >= 0 || e.c.indexOf(q) === 0) out.push(e)
        }
        return out
    }
    function has(l, v) { for (var i = 0; i < picked.length; i++) if (picked[i].l === l && picked[i].v === v) return true; return false }
    function add(l, v) { if (has(l, v) || picked.length >= 8) return; picked = picked.concat([{ l: l, v: v }]); changed() }
    function remove(i) { if (picked.length < 2) return; var a = picked.slice(); a.splice(i, 1); picked = a; changed() }
    function earlier(i) { if (i < 1) return; var a = picked.slice(); var t = a[i]; a[i] = a[i - 1]; a[i - 1] = t; picked = a; changed() }
    function setToggle(t) { toggle = t; changed() }

    Process { command: ["/usr/local/bin/smof-input", "list"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { var o = JSON.parse(text); lp.all = o.layouts; lp.toggles = o.toggles } catch (e) {} } } }

    Column {
        id: col
        width: parent.width
        spacing: 14
        T { text: "In use"; font.pixelSize: 15; w: 600; color: Theme.i55 }
        Flow {
            width: parent.width; spacing: 8
            Repeater {
                model: lp.picked
                Rectangle {
                    required property var modelData
                    required property int index
                    height: 38; radius: 19; color: index === 0 ? Theme.acc : Theme.i12
                    width: chipRow.implicitWidth + 28
                    Row {
                        id: chipRow
                        x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                        T { anchors.verticalCenter: parent.verticalCenter; text: lp.nameOf(modelData); font.pixelSize: 15; w: 560; color: index === 0 ? Theme.onacc : Theme.ink }
                        Item { visible: index > 0; width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                            T { anchors.centerIn: parent; text: "‹"; font.pixelSize: 20; color: Theme.ink }
                            MouseArea { anchors.fill: parent; onClicked: lp.earlier(index) } }
                        Item { visible: lp.picked.length > 1; width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                            T { anchors.centerIn: parent; text: "×"; font.pixelSize: 20; color: index === 0 ? Theme.onacc : Theme.ink }
                            MouseArea { anchors.fill: parent; onClicked: lp.remove(index) } }
                    }
                }
            }
        }
        Column {
            visible: lp.picked.length > 1
            width: parent.width; spacing: 8
            T { text: "Switch with"; font.pixelSize: 15; w: 600; color: Theme.i55 }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: lp.toggles
                    Rectangle {
                        required property var modelData
                        height: 34; width: tt.implicitWidth + 28; radius: 17
                        color: lp.toggle === modelData.c ? Theme.acc : "transparent"; border.width: 1.5; border.color: lp.toggle === modelData.c ? "transparent" : Theme.i12
                        T { id: tt; anchors.centerIn: parent; text: modelData.n; font.pixelSize: 14; w: lp.toggle === modelData.c ? 650 : 480; color: lp.toggle === modelData.c ? Theme.onacc : Theme.ink }
                        MouseArea { anchors.fill: parent; onClicked: lp.setToggle(modelData.c) }
                    }
                }
            }
        }
        T { text: "Add a layout"; font.pixelSize: 15; w: 600; color: Theme.i55 }
        Rectangle {
            width: parent.width; height: 44; radius: 22; color: Theme.cardbg; border.width: 1; border.color: Theme.i12
            T { visible: sin.text === ""; x: 18; anchors.verticalCenter: parent.verticalCenter; text: "Search languages"; font.pixelSize: 16; color: Theme.i5 }
            TextInput { id: sin; x: 18; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter; font.family: "Google Sans Flex"; font.pixelSize: 16; color: Theme.ink; clip: true
                onTextChanged: lp.query = text }
        }
        Rectangle {
            width: parent.width; height: lp.listHeight; radius: 22; color: Theme.cardbg; clip: true
            ListView {
                SmoothWheel {}
                id: lv
                anchors.fill: parent; anchors.margins: 6
                model: lp.shown
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    required property var modelData
                    readonly property bool exp: lp.open === modelData.c
                    width: lv.width
                    height: 42 + (exp ? vflow.implicitHeight + 12 : 0)
                    Rectangle { x: 0; y: 0; width: parent.width; height: 42; radius: 16; color: Theme.acc; opacity: rma.containsMouse ? .12 : 0 }
                    T { x: 14; y: 0; height: 42; verticalAlignment: Text.AlignVCenter; width: parent.width - 120; elide: Text.ElideRight; text: modelData.n; font.pixelSize: 16 }
                    T { anchors.right: parent.right; anchors.rightMargin: 14; y: 0; height: 42; verticalAlignment: Text.AlignVCenter; text: modelData.v.length > 0 ? (exp ? "˄" : "˅") : (lp.has(modelData.c, "") ? "added" : "Add"); font.pixelSize: 14; color: Theme.acc; w: 600 }
                    MouseArea { id: rma; x: 0; y: 0; width: parent.width; height: 42; hoverEnabled: true
                        onClicked: { if (modelData.v.length > 0) lp.open = exp ? "" : modelData.c; else lp.add(modelData.c, "") } }
                    Flow {
                        id: vflow
                        visible: exp
                        x: 14; y: 46; width: parent.width - 28; spacing: 6
                        Repeater {
                            model: exp ? [{ c: "", n: "Standard" }].concat(modelData.v) : []
                            Rectangle {
                                required property var modelData
                                height: 30; width: vt.implicitWidth + 24; radius: 15; color: Theme.i12
                                T { id: vt; anchors.centerIn: parent; text: modelData.n; font.pixelSize: 13 }
                                MouseArea { anchors.fill: parent; onClicked: { lp.add(lp.open, modelData.c) } }
                            }
                        }
                    }
                }
            }
        }
    }
}
