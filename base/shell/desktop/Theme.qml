pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// light and dark colors of Smof, the choice is kept in /var/lib/smof/theme so the lock screen and the desktop agree
Singleton {
    id: t
    property bool dark: false
    readonly property string sfx: dark ? "-d" : ""

    readonly property color ink: dark ? "#F4F0FF" : "#171229"
    readonly property color i55: dark ? Qt.rgba(.957, .941, 1, .62) : Qt.rgba(.09, .07, .16, .55)
    readonly property color i62: dark ? Qt.rgba(.957, .941, 1, .72) : Qt.rgba(.09, .07, .16, .62)
    readonly property color i5:  dark ? Qt.rgba(.957, .941, 1, .55) : Qt.rgba(.09, .07, .16, .50)
    readonly property color i8:  dark ? Qt.rgba(.957, .941, 1, .86) : Qt.rgba(.09, .07, .16, .80)
    readonly property color i6:  dark ? Qt.rgba(.957, .941, 1, .66) : Qt.rgba(.09, .07, .16, .60)
    readonly property color i12: dark ? Qt.rgba(.957, .941, 1, .16) : Qt.rgba(.09, .07, .16, .12)
    readonly property color i9:  dark ? Qt.rgba(.957, .941, 1, .92) : Qt.rgba(.09, .07, .16, .90)
    readonly property color onacc: dark ? "#171229" : "#FFFFFF"
    readonly property color acc: dark ? "#B9A2FF" : "#6B4FA8"
    readonly property color acc2: dark ? "#A58CF0" : "#8B6FD6"
    readonly property color moonbg: dark ? Qt.rgba(.725, .635, 1, .24) : "#E4DAF8"
    readonly property color glass: dark ? Qt.rgba(.133, .102, .282, .34) : Qt.rgba(1, 1, 1, .26)
    readonly property color glassBorder: dark ? Qt.rgba(1, 1, 1, .16) : Qt.rgba(1, 1, 1, .45)
    readonly property color sysbg: dark ? "#4A2B34" : "#FFE1D6"
    readonly property color pxbg: dark ? "#1F4538" : "#D8F2E6"
    readonly property color yelbg: dark ? Qt.rgba(1, .84, .42, .2) : "#FFF1C9"
    readonly property color errbg: dark ? "#4A2B34" : "#FFE1D6"
    readonly property color errfg: dark ? "#FFB59E" : "#B3401C"
    readonly property color warnbg: dark ? Qt.rgba(1, .84, .42, .2) : "#FFF1C9"
    readonly property color warnfg: dark ? "#FFD66B" : "#8A5A00"
    function lvBg(l) { return l === "error" ? errbg : (l === "warning" ? warnbg : moonbg) }
    function lvFg(l) { return l === "error" ? errfg : (l === "warning" ? warnfg : acc) }
    readonly property color winbg: dark ? "#1B1630" : "#F7F4FC"
    readonly property color sidebg: dark ? "#150F27" : "#EEE9F8"
    readonly property color cardbg: dark ? "#262040" : "#FFFFFF"
    readonly property color glass2: dark ? Qt.rgba(1, 1, 1, .10) : Qt.rgba(1, 1, 1, .50)
    readonly property color panelbg: dark ? Qt.rgba(.118, .094, .251, .55) : Qt.rgba(1, 1, 1, .45)
    readonly property color menubg: dark ? Qt.rgba(.118, .094, .251, .94) : Qt.rgba(1, 1, 1, .92)
    readonly property color pill: dark ? Qt.rgba(.04, .03, .12, .42) : Qt.rgba(.157, .11, .314, .30)

    // read the saved choice right away, before anything is drawn, so the wrong wallpaper never flashes
    Component.onCompleted: { try { t.dark = fv.text().trim() === "dark" } catch (e) {} }

    function save() { fv.setText(dark ? "dark" : "light") }
    function setDark(d, persist) { if (dark !== d) { dark = d; if (persist) save() } }
    function apply(d) { if (dark !== d) toggle() }
    function toggle() { dark = !dark; save(); Quickshell.execDetached(["/usr/local/bin/smof-wm-theme", dark ? "dark" : "light"]) }

    FileView {
        id: fv
        path: "/var/lib/smof/theme"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: t.dark = text().trim() === "dark"
    }
}
