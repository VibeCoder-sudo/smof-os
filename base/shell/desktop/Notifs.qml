pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// the notification service of Smof: apps talk to it over D-Bus (notify-send works).
// Every notification is copied into our own list, which is saved to a file in the home folder, so it survives a restart.
Singleton {
    id: n
    readonly property ListModel store: ListModel {}     // the list in the panel, newest first
    readonly property ListModel toasts: ListModel {}    // cards shown at the top right for a few seconds
    readonly property int count: store.count
    property bool panelOpen: false      // set by the panel over IPC, pop-ups hide while it is open
    property int seq: 0
    property bool ready: false
    readonly property string file: Quickshell.env("HOME") + "/.local/state/smof-notifs.json"

    // error, warning or info: critical urgency or an error icon is an error, a warning icon is a warning
    function levelOf(urgency, icon) {
        var ic = (icon || "").toLowerCase()
        if (urgency === NotificationUrgency.Critical || ic.indexOf("error") >= 0) return "error"
        if (ic.indexOf("warn") >= 0) return "warning"
        return "info"
    }

    // one by one, so every card gets its leaving animation (clear() would drop them all at once and leave artifacts)
    function clearAll() { toasts.clear(); if (store.count > 0) clearT.start() }
    Timer { id: clearT; interval: 70; repeat: true; onTriggered: { if (n.store.count > 0) n.store.remove(0); if (n.store.count === 0) { stop(); n.save() } } }
    function remove(id) {
        if (live[id]) { try { live[id].dismiss() } catch (e) {} delete live[id] }
        for (var i = 0; i < store.count; i++) if (store.get(i).nid === id) { store.remove(i); break }
        hideToast(id)
        Ui.sound(level === "error" ? "error" : (level === "warning" ? "warning" : "notify"))
        save()
    }
    // while the cursor is on a toast it stays; a short moment after the cursor leaves it goes
    function setHover(id, on) {
        for (var i = 0; i < toasts.count; i++) if (toasts.get(i).nid === id && !toasts.get(i).hide) {
            toasts.setProperty(i, "hover", on)
            if (!on) toasts.setProperty(i, "until", Date.now() + 1500)
        }
    }
    function invoke(id, ident) {
        var nt = live[id]
        if (nt) for (var i = 0; i < nt.actions.length; i++) if (nt.actions[i].identifier === ident) { nt.actions[i].invoke(); break }
        hideToast(id)
    }
    function hideToast(id) {
        for (var i = 0; i < toasts.count; i++) if (toasts.get(i).nid === id) { toasts.setProperty(i, "hide", true); toasts.setProperty(i, "gone", Date.now() + 450) }
    }

    property var live: ({})      // the real notification objects, kept so their action buttons can be pressed

    function add(app, summary, body, level, actions, nt) {
        var id = Date.now() * 1000 + (seq++ % 1000)
        if (nt) live[id] = nt
        var life = level === "error" ? 10000 : (level === "warning" ? 8000 : 5500)
        store.insert(0, { nid: id, app: app, summary: summary, body: body, level: level, time: Date.now() })
        while (store.count > 60) store.remove(store.count - 1)
        // the status pill already shows a screenshot, so its notification only goes into the list and does not cover the pill
        if (!Ui.dnd && app !== "Screenshot") toasts.append({ nid: id, app: app, summary: summary, body: body, level: level, until: Date.now() + life, gone: 0, hide: false, hover: false, actions: JSON.stringify(actions || []) })
        save()
    }

    function save() { if (ready) saveT.restart() }
    Timer {
        id: saveT; interval: 400
        onTriggered: {
            var a = []
            for (var i = 0; i < store.count; i++) { var o = store.get(i); a.push({ nid: o.nid, app: o.app, summary: o.summary, body: o.body, level: o.level, time: o.time }) }
            fv.setText(JSON.stringify(a))
        }
    }
    FileView {
        id: fv
        path: n.file
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        try {
            var a = JSON.parse(fv.text())
            for (var i = 0; i < a.length; i++) store.append(a[i])
        } catch (e) {}
        ready = true
    }

    IpcHandler { target: "notifs"
        function remove(id: string): void { n.remove(Number(id)) }
        function clear(): void { n.clearAll() }
        function panel(open: bool): void { n.panelOpen = open } }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: false
        onNotification: (nt) => {
            var lv = n.levelOf(nt.urgency, (nt.appIcon || "") + " " + (nt.image || ""))
            nt.tracked = true
            var acts = []
            for (var i = 0; i < nt.actions.length; i++) if (nt.actions[i].identifier !== "default") acts.push({ id: nt.actions[i].identifier, text: nt.actions[i].text })
            n.add(nt.appName || "", nt.summary || "", nt.body || "", lv, acts, nt)
        }
    }

    // toasts first fade out (hide), then are removed
    Timer {
        interval: 250; repeat: true; running: n.toasts.count > 0
        onTriggered: {
            var now = Date.now()
            for (var i = n.toasts.count - 1; i >= 0; i--) {
                var t = n.toasts.get(i)
                if (t.hide) { if (t.gone < now) n.toasts.remove(i) }
                else if (!t.hover && t.until < now) n.hideToast(t.nid)
            }
        }
    }
}
