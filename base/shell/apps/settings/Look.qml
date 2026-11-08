pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// how the system looks, chosen in Settings: accent colour, wallpapers, clock, dock. Saved in /var/lib/smof/look.json,
// a place the lock screen can read too, so the lock screen and the desktop follow the same choices.
Singleton {
    id: l

    readonly property var accents: [
        { name: "Violet", l: "#6B4FA8", d: "#B9A2FF" },
        { name: "Blue",   l: "#3A62C9", d: "#9DB8FF" },
        { name: "Pink",   l: "#B54488", d: "#FFA6D5" },
        { name: "Green",  l: "#2B8561", d: "#8FE0B8" },
        { name: "Orange", l: "#C2602A", d: "#FFBC8A" }
    ]
    readonly property var gradients: [
        { id: "g-dusk",  name: "Dusk",  l1: "#F6C1D8", l2: "#8E7BDB", d1: "#4B2F6E", d2: "#171229" },
        { id: "g-ocean", name: "Ocean", l1: "#BFE3F7", l2: "#4F7FD6", d1: "#1E3A66", d2: "#0C1530" },
        { id: "g-mint",  name: "Mint",  l1: "#D5F2E0", l2: "#58B596", d1: "#1D4A3C", d2: "#0B1F1A" },
        { id: "g-ember", name: "Ember", l1: "#FFD9B3", l2: "#E0745A", d1: "#6B2E22", d2: "#1F0E12" }
    ]

    // ---- the choices ----
    property int accent: 0
    property string wpMode: "dunes"          // dunes, g-dusk, g-ocean, g-mint, g-ember, image
    property string wpImage: ""
    property real wpDim: 0                    // 0 to 0.5, a dark veil over the wallpaper
    property string lockMode: "same"          // same as the desktop, or any wallpaper mode
    property string lockImage: ""
    property bool clock24: true
    property bool barDate: true
    property int dockSize: 60                 // biggest size of a dock tile
    property real lockClock: 1.0              // size of the lock screen clock
    property bool lockCenter: false           // clock in the middle instead of the left
    property bool lockDate: true
    property bool sounds: true                // system sounds
    property real soundVol: 0.8

    property bool _ready: false
    property bool _applying: false
    property string _last: ""
    function _data() {
        return JSON.stringify({ accent: accent, wpMode: wpMode, wpImage: wpImage, wpDim: Math.round(wpDim * 100) / 100, lockMode: lockMode, lockImage: lockImage,
            clock24: clock24, barDate: barDate, dockSize: dockSize, lockClock: lockClock, lockCenter: lockCenter, lockDate: lockDate, sounds: sounds, soundVol: Math.round(soundVol * 100) / 100 })
    }
    function _saveSoon() { if (_ready && !_applying) saveT.restart() }
    onAccentChanged: _saveSoon()
    onWpModeChanged: _saveSoon()
    onWpImageChanged: _saveSoon()
    onWpDimChanged: _saveSoon()
    onLockModeChanged: _saveSoon()
    onLockImageChanged: _saveSoon()
    onClock24Changed: _saveSoon()
    onBarDateChanged: _saveSoon()
    onDockSizeChanged: _saveSoon()
    onLockClockChanged: _saveSoon()
    onLockCenterChanged: _saveSoon()
    onLockDateChanged: _saveSoon()
    onSoundsChanged: _saveSoon()
    onSoundVolChanged: _saveSoon()
    Timer { id: saveT; interval: 200; onTriggered: { var d = l._data(); if (d !== l._last) { l._last = d; fv.setText(d) } } }

    function _apply(t) {
        try {
            var o = JSON.parse(t); _applying = true
            if (o.accent !== undefined) accent = Math.max(0, Math.min(accents.length - 1, o.accent))
            if (o.wpMode !== undefined) wpMode = o.wpMode
            if (o.wpImage !== undefined) wpImage = o.wpImage
            if (o.wpDim !== undefined) wpDim = o.wpDim
            if (o.lockMode !== undefined) lockMode = o.lockMode
            if (o.lockImage !== undefined) lockImage = o.lockImage
            if (o.clock24 !== undefined) clock24 = !!o.clock24
            if (o.barDate !== undefined) barDate = !!o.barDate
            if (o.dockSize !== undefined) dockSize = o.dockSize
            if (o.lockClock !== undefined) lockClock = o.lockClock
            if (o.lockCenter !== undefined) lockCenter = !!o.lockCenter
            if (o.lockDate !== undefined) lockDate = !!o.lockDate
            if (o.sounds !== undefined) sounds = !!o.sounds
            if (o.soundVol !== undefined) soundVol = o.soundVol
            _last = _data()
        } catch (e) {}
        _applying = false
    }
    FileView { id: fv; path: Quickshell.env("SMOF_LOOK") || "/var/lib/smof/look.json"; blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: reload(); onLoaded: l._apply(fv.text()) }
    Component.onCompleted: { try { _apply(fv.text()) } catch (e) {} _ready = true }
}
