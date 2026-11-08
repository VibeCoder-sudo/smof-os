import QtQuick

// the same picture as the boot splash: night dunes, the Smof wordmark and the spinner
Item {
    id: so
    readonly property real k: Math.max(width / 1920, height / 1200)
    readonly property real ox: (width - 1920 * k) / 2
    readonly property real oy: (height - 1200 * k) / 2
    readonly property string dir: "file:///usr/share/plymouth/themes/smof/"
    Image { x: so.ox; y: so.oy; width: 1920 * so.k; height: 1200 * so.k; source: so.dir + "background.png"; smooth: true }
    Image { x: so.ox + 581 * so.k; y: so.oy + 220 * so.k; width: 757 * so.k; height: 585 * so.k; source: so.dir + "smof-wordmark.png"; smooth: true }
    Spinner { x: so.ox + 890 * so.k; y: so.oy + 720 * so.k; width: 140 * so.k; height: 140 * so.k; active: so.visible }
}
