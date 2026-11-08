pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// state shared by all Smof apps. The persistent parts live in files in the home folder and every app watches them,
// so a switch flipped in Settings changes the bar, the dock and the wallpaper, which are other processes.
Singleton {
    id: ui
    readonly property string home: Quickshell.env("HOME")

    // ---- window behaviour, ~/.config/smof-windows.json (the zone tiler reads the same file) ----
    property bool tiling: true         // new windows share the screen in zones
    property int tileGap: 10
    property int tileSide: 12
    property bool tileClear: true     // keep tiles clear of the bar and the dock
    property bool autohide: true       // bar and dock step aside when a window fills the screen

    // ---- quick settings, ~/.config/smof-prefs.json ----
    property bool dnd: false
    property bool calm: false
    property bool lowpower: false
    property real brightness: 1.0      // 0.3 to 1, applied as a dark veil over everything

    property bool _ready: false
    property bool _applying: false
    property string _lastWin: ""
    property string _lastPrefs: ""

    function _saveSoon() { if (_ready && !_applying) saveT.restart() }
    onTilingChanged: _saveSoon()
    onTileGapChanged: _saveSoon()
    onTileSideChanged: _saveSoon()
    onTileClearChanged: _saveSoon()
    onAutohideChanged: _saveSoon()
    onDndChanged: _saveSoon()
    onCalmChanged: _saveSoon()
    onLowpowerChanged: _saveSoon()
    onBrightnessChanged: _saveSoon()
    Timer {
        id: saveT; interval: 150
        onTriggered: {
            var w = JSON.stringify({ tiling: ui.tiling, gap: ui.tileGap, side: ui.tileSide, clear: ui.tileClear, autohide: ui.autohide })
            if (w !== ui._lastWin) { ui._lastWin = w; wf.setText(w) }
            var p = JSON.stringify({ dnd: ui.dnd, calm: ui.calm, lowpower: ui.lowpower, brightness: Math.round(ui.brightness * 100) / 100 })
            if (p !== ui._lastPrefs) { ui._lastPrefs = p; pf.setText(p) }
        }
    }
    function _applyWin(t) {
        try {
            var o = JSON.parse(t); _applying = true
            if (o.tiling !== undefined && tiling !== !!o.tiling) tiling = !!o.tiling
            if (o.gap !== undefined && tileGap !== o.gap) tileGap = o.gap
            if (o.side !== undefined && tileSide !== o.side) tileSide = o.side
            if (o.clear !== undefined && tileClear !== !!o.clear) tileClear = !!o.clear
            if (o.autohide !== undefined && autohide !== !!o.autohide) autohide = !!o.autohide
            _lastWin = JSON.stringify({ tiling: tiling, gap: tileGap, side: tileSide, clear: tileClear, autohide: autohide })
        } catch (e) {}
        _applying = false
    }
    function _applyPrefs(t) {
        try {
            var o = JSON.parse(t); _applying = true
            if (o.dnd !== undefined && dnd !== !!o.dnd) dnd = !!o.dnd
            if (o.calm !== undefined && calm !== !!o.calm) calm = !!o.calm
            if (o.lowpower !== undefined && lowpower !== !!o.lowpower) lowpower = !!o.lowpower
            if (o.brightness !== undefined && Math.abs(brightness - o.brightness) > 0.004) brightness = o.brightness
            _lastPrefs = JSON.stringify({ dnd: dnd, calm: calm, lowpower: lowpower, brightness: Math.round(brightness * 100) / 100 })
        } catch (e) {}
        _applying = false
    }
    FileView { id: wf; path: ui.home + "/.config/smof-windows.json"; blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: reload(); onLoaded: ui._applyWin(wf.text()) }
    FileView { id: pf; path: ui.home + "/.config/smof-prefs.json"; blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: reload(); onLoaded: ui._applyPrefs(pf.text()) }
    Component.onCompleted: {
        try { _applyWin(wf.text()) } catch (e) {}
        try { _applyPrefs(pf.text()) } catch (e) {}
        _ready = true
    }

    // ---- flags of this process only ----
    property bool panelOpen: false
    property bool menuOpen: false      // a bar or dock menu is open
    property bool entered: false       // flips shortly after the app starts, everything fades in from it
    Timer { running: true; interval: 350; onTriggered: ui.entered = true }
    signal dismiss()

    function closeAll() { panelOpen = false; menuOpen = false; dismiss() }
    function togglePanel() { if (panelOpen) { closeAll() } else { closeAll(); closeOther("dock"); panelOpen = true } }

    // ---- talking to other Smof apps ----
    function run(args) { Quickshell.execDetached(args) }
    function ipc(app, target, fn, arg) {
        var a = ["/usr/local/bin/smof-ipc", app, target, fn]
        if (arg !== undefined) a.push(String(arg))
        Quickshell.execDetached(a)
    }
    function closeOther(app) { ipc(app, "ui", "close") }
    function openSettings(page) { run(["/usr/local/bin/smof-settings", page || ""]) }
    function toggleLauncher() { ipc("launcher", "launcher", "toggle") }
    // the notification pop-ups hide while the panel is open
    onPanelOpenChanged: ipc("notifd", "notifs", "panel", panelOpen ? "true" : "false")
}
