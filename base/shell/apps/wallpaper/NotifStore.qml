pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// the saved notifications as seen by the bar, the panel and Settings. The daemon (smof notifd) owns the list,
// this follows its file and asks it over IPC to remove things.
Singleton {
    id: s
    readonly property ListModel store: ListModel {}
    readonly property int count: store.count

    function _ids() { var o = {}; for (var i = 0; i < store.count; i++) o[store.get(i).nid] = i; return o }
    function sync(t) {
        var a
        try { a = JSON.parse(t) } catch (e) { return }
        if (!Array.isArray(a)) return
        var want = {}
        for (var i = 0; i < a.length; i++) want[a[i].nid] = true
        for (var k = store.count - 1; k >= 0; k--) if (!want[store.get(k).nid]) store.remove(k)
        var have = _ids()
        for (var j = 0; j < a.length; j++) if (have[a[j].nid] === undefined) { store.insert(Math.min(j, store.count), a[j]); have = _ids() }
    }
    FileView { id: fv; path: Quickshell.env("HOME") + "/.local/state/smof-notifs.json"; blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: reload(); onLoaded: s.sync(fv.text()) }
    Component.onCompleted: { try { sync(fv.text()) } catch (e) {} }

    function remove(id) {
        for (var i = 0; i < store.count; i++) if (store.get(i).nid === id) { store.remove(i); break }
        Ui.ipc("notifd", "notifs", "remove", id)
    }
    // one by one so every card leaves with its animation
    function clearAll() { if (store.count > 0) clearT.start(); Ui.ipc("notifd", "notifs", "clear") }
    Timer { id: clearT; interval: 70; repeat: true; onTriggered: { if (s.store.count > 0) s.store.remove(0); if (s.store.count === 0) stop() } }
}
