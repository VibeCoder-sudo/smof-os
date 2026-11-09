import Quickshell
import Quickshell.Io
import QtQuick

FloatingWindow {
    id: win
    title: "Smof Store"
    readonly property real scrW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1366
    readonly property real scrH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 768
    // never larger than the screen minus the bar and the dock
    implicitWidth: Math.min(1180, scrW - 24)
    implicitHeight: Math.min(780, scrH - 210)
    minimumSize: Qt.size(Math.min(820, implicitWidth), Math.min(560, implicitHeight))
    color: Theme.winbg
    visible: true
    onVisibleChanged: if (!visible) Qt.quit()

    // ---- data ----
    property var pacCat: []
    property var brewCat: []
    property var idx: ({})                       // "source:name" to entry
    property var byName: ({})                    // name to entries
    property var topRank: ({})                   // "source:name" to place in the charts
    property var pacTop: []
    property var brewTop: []
    property var aurRes: []
    property bool aurBusy: false
    property string aurErr: ""
    property var pac: ({ all: {}, explicit: [], outdated: {} })
    property var brew: ({ leaves: [], all: {}, outdated: {} })
    property var own: []
    property real free: 0
    property bool brewOk: true
    property int loaded: 0
    readonly property bool ready: loaded >= 2
    readonly property bool compact: width < 720

    property string page: "discover"             // discover, installed, updates, search, cat:ID
    property string viewKey: ""
    property string query: ""
    property string srcFilter: "all"             // all, pacman, brew, aur
    property string showFilter: "all"            // all, installed, new
    property string sortBy: "relevance"          // relevance, name, size, popular
    property var jobsList: []                    // what smof-pkg jobs says, jobs live on when this window is closed
    property var stages: ({})
    property var progs: ({})
    readonly property var active: jobsList.filter(function (j) { return j.status === "queued" || j.status === "running" })
    readonly property var cur: { var r = active.filter(function (j) { return j.status === "running" }); return r.length ? r[0] : (active.length ? active[0] : null) }
    readonly property var queue: active.filter(function (j) { return !cur || j.id !== cur.id })
    readonly property string stage: cur ? (stages[cur.id] || (cur.status === "queued" ? "Waiting for another installation" : "Working")) : ""
    readonly property real prog: cur && progs[cur.id] !== undefined ? progs[cur.id] : -1
    property bool logOpen: false
    property var logLines: []
    property var reported: ({})
    function setProg(id, st, pr) {
        var a = Object.assign({}, stages), b = Object.assign({}, progs)
        a[id] = st; if (pr >= 0) b[id] = pr
        stages = a; progs = b
    }
    function readLine(l, id) {
        var stage = "", prog = progs[id] === undefined ? -1 : progs[id]
        var m = /\((\d+)\/(\d+)\)\s+(.*)/.exec(l)
        if (m) {
            var n = parseInt(m[1]), t = parseInt(m[2]), w = m[3].toLowerCase()
            stage = /install/.test(w) ? "Installing" : (/upgrad/.test(w) ? "Updating" : (/remov/.test(w) ? "Removing" : (/hook|running|trigger|reload|updating|arming|creating|checking/.test(w) ? "Finishing" : "Working")))
            if (/checking|loading|resolv/.test(w)) stage = "Checking"
            var v = 0.5 + 0.5 * (n - 1) / t
            if (stage === "Checking") v = 0.05 + 0.1 * (n - 1) / t
            prog = Math.max(prog, Math.min(0.99, v)); setProg(id, stage, prog); return
        }
        var pc = /(\d{1,3})%\s*$/.exec(l)
        if (pc) { stage = "Downloading"; prog = Math.max(prog, Math.min(0.45, 0.05 + 0.4 * parseInt(pc[1]) / 100)); setProg(id, stage, prog); return }
        if (/retrieving|downloading|cloning|fetching/i.test(l)) { stage = "Downloading"; prog = Math.max(prog, 0.05); setProg(id, stage, prog); return }
        if (/pouring|installing|building|compiling|==> .*make/i.test(l)) { stage = /building|compiling|make/i.test(l) ? "Building" : "Installing"; setProg(id, stage, prog); return }
        if (/waiting for permission/i.test(l)) setProg(id, "Waiting for permission", prog)
        if (/waiting for (another|the other)/i.test(l)) setProg(id, "Waiting for another installation", prog)
    }
    property string lastErr: ""
    property string note: ""
    property string noteKind: "info"
    property var confirm: null                   // AUR install waiting for a yes
    property var aurArch: null

    readonly property var srcs: [ { id: "pacman", name: "Pacman", tint: 0.6 }, { id: "brew", name: "Homebrew", tint: 0.09 }, { id: "aur", name: "AUR", tint: 0.8 } ]
    readonly property var cats: [
        { id: "web", name: "Web and mail", tint: 0.58, apps: ["firefox", "chromium", "epiphany", "falkon", "qutebrowser", "thunderbird", "links", "w3m", "lynx", "curl", "wget"] },
        { id: "media", name: "Media and graphics", tint: 0.04, apps: ["vlc", "mpv", "gimp", "inkscape", "krita", "audacity", "obs-studio", "blender", "handbrake", "ffmpeg", "imagemagick", "yt-dlp", "sox", "cmus", "chafa", "graphviz", "exiftool", "optipng", "gifsicle"] },
        { id: "office", name: "Office and reading", tint: 0.12, apps: ["libreoffice-fresh", "evince", "zathura", "okular", "calibre", "pandoc", "typst", "poppler", "ghostscript", "tesseract"] },
        { id: "dev", name: "Developer tools", tint: 0.62, apps: ["git", "github-cli", "gh", "nodejs", "node", "python", "go", "rust", "cmake", "meson", "neovim", "vim", "helix", "gdb", "valgrind", "lazygit", "git-delta", "just", "deno", "bun", "uv", "ruby", "jdk-openjdk", "llvm", "shellcheck", "hyperfine", "tokei"] },
        { id: "term", name: "System and terminal", tint: 0.5, apps: ["btop", "htop", "nvtop", "tmux", "zellij", "fastfetch", "ncdu", "gparted", "rsync", "yazi", "fzf", "ripgrep", "bat", "eza", "fd", "zoxide", "starship", "tldr", "dust", "procs", "fish", "zsh", "nushell", "glow"] },
        { id: "data", name: "Data", tint: 0.35, apps: ["sqlite", "postgresql", "redis", "duckdb", "jq", "yq", "miller", "csvkit", "visidata", "gnuplot"] },
        { id: "fun", name: "Just for fun", tint: 0.88, apps: ["cowsay", "figlet", "lolcat", "cmatrix", "sl", "asciiquarium", "pipes-sh", "nyancat", "fortune-mod", "toilet", "cbonsai", "genact", "hollywood", "cava", "tty-clock"] }
    ]
    readonly property var popularPac: ["firefox", "chromium", "vlc", "mpv", "gimp", "inkscape", "libreoffice-fresh", "obs-studio", "audacity", "blender", "krita", "thunderbird", "neovim", "btop", "htop", "tmux", "git", "ffmpeg", "yt-dlp", "evince", "zathura", "okular", "calibre", "epiphany", "falkon", "qutebrowser", "gparted", "nvtop", "fastfetch", "ripgrep", "fzf", "bat", "eza", "yazi"]

    // ---- small helpers ----
    function key(e) { return e.s + ":" + e.n }
    function srcName(s) { return s === "pacman" ? "Pacman" : (s === "brew" ? "Homebrew" : "AUR") }
    function srcTint(s) { return s === "pacman" ? 0.6 : (s === "brew" ? 0.09 : 0.8) }
    function isInst(e) { return e.s === "brew" ? brew.all[e.n] !== undefined : pac.all[e.n] !== undefined }
    function isOut(e) { return e.s === "brew" ? brew.outdated[e.n] !== undefined : pac.outdated[e.n] !== undefined }
    function outInfo(e) { return e.s === "brew" ? brew.outdated[e.n] : pac.outdated[e.n] }
    function canRemove(e) { return e.s === "brew" ? brew.leaves.indexOf(e.n) >= 0 : own.indexOf(e.n) >= 0 }
    function jobOf(e) { for (var i = 0; i < active.length; i++) if (active[i].src === e.s && active[i].n === e.n) return active[i]; return null }
    function isCur(e) { return !!cur && cur.src === e.s && cur.n === e.n }
    function hue(n) { var h = 0; for (var i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) % 360; return h / 360 }
    function tileBg(n) { return Qt.hsla(hue(n), Theme.dark ? 0.42 : 0.55, Theme.dark ? 0.30 : 0.84, 1) }
    function tileFg(n) { return Qt.hsla(hue(n), Theme.dark ? 0.75 : 0.55, Theme.dark ? 0.84 : 0.30, 1) }
    function pretty(n) { var s = n.replace(/@.*/, ""); return s.charAt(0).toUpperCase() + s.slice(1) }
    function fmtSize(n) { if (!n) return ""; if (n < 1048576) return Math.max(1, Math.round(n / 1024)) + " KB"; if (n < 1073741824) return (n / 1048576).toFixed(n < 10485760 ? 1 : 0) + " MB"; return (n / 1073741824).toFixed(1) + " GB" }
    readonly property int pacOutCount: Object.keys(pac.outdated).length
    readonly property int brewOutCount: Object.keys(brew.outdated).length
    readonly property int outCount: pacOutCount + brewOutCount

    function passes(e) {
        if (srcFilter !== "all" && e.s !== srcFilter) return false
        var inst = isInst(e)
        if (showFilter === "installed" && !inst) return false
        if (showFilter === "new" && inst) return false
        return true
    }
    function sortList(arr) {
        var a = arr.slice()
        if (sortBy === "name") a.sort(function (x, y) { return x.n < y.n ? -1 : (x.n > y.n ? 1 : 0) })
        else if (sortBy === "size") a.sort(function (x, y) { return (y.sz || 0) - (x.sz || 0) })
        else if (sortBy === "popular") a.sort(function (x, y) { return (topRank[key(x)] === undefined ? 99999 : topRank[key(x)]) - (topRank[key(y)] === undefined ? 99999 : topRank[key(y)]) })
        return a
    }
    function entriesNamed(names) {
        var out = []
        for (var i = 0; i < names.length; i++) {
            var l = byName[names[i]] || []
            for (var j = 0; j < l.length; j++) out.push(l[j])
        }
        return out
    }
    function catById(id) { for (var i = 0; i < cats.length; i++) if (cats[i].id === id) return cats[i]; return null }
    function listOfCat(c) {
        // one row per name: the first source that has it, unless a source is picked
        var out = [], seen = {}
        for (var i = 0; i < c.apps.length; i++) {
            var l = byName[c.apps[i]] || []
            for (var j = 0; j < l.length; j++) { var e = l[j]; if (!passes(e)) continue; if (srcFilter === "all" && seen[e.n]) continue; seen[e.n] = true; out.push(e) }
        }
        return sortList(out)
    }

    readonly property var results: {
        var q = query.trim().toLowerCase()
        if (q === "") return []
        var a = [], b = [], c = [], d = []
        var lists = [pacCat, brewCat]
        for (var k = 0; k < lists.length; k++) {
            var cat = lists[k]
            for (var i = 0; i < cat.length; i++) {
                var e = cat[i], n = e.n.toLowerCase()
                if (srcFilter !== "all" && e.s !== srcFilter) continue
                if (n === q) a.push(e)
                else if (n.indexOf(q) === 0) b.push(e)
                else if (n.indexOf(q) > 0) c.push(e)
                else if (q.length > 2 && e.d.toLowerCase().indexOf(q) >= 0) d.push(e)
            }
        }
        var all = a.concat(b, c, d).filter(function (e) { return passes(e) })
        return sortList(all.slice(0, 160)).slice(0, 100)
    }
    readonly property var aurShown: (srcFilter === "all" || srcFilter === "aur") ? aurRes.filter(function (e) { return passes(e) }) : []
    readonly property var topApps: {
        var out = []
        var pl = []
        if (srcFilter !== "brew") for (var i = 0; i < popularPac.length; i++) { var e = idx["pacman:" + popularPac[i]]; if (e) pl.push(e) }
        var bl = []
        if (srcFilter !== "pacman" && srcFilter !== "aur") for (var j = 0; j < brewTop.length && bl.length < 14; j++) { var f = idx["brew:" + brewTop[j]]; if (f && f.d !== "") bl.push(f) }
        var n = Math.max(pl.length, bl.length)
        for (var k = 0; k < n; k++) { if (k < pl.length) out.push(pl[k]); if (k < bl.length) out.push(bl[k]) }
        return sortList(out.filter(function (e) { return passes(e) })).slice(0, 14)
    }
    readonly property var installedApps: {
        var out = []
        for (var i = 0; i < pac.explicit.length; i++) { var n = pac.explicit[i]; var e = idx["pacman:" + n]; out.push(e ? e : { s: own.indexOf(n) >= 0 ? "aur" : "pacman", n: n, d: "", v: pac.all[n] || "", h: "", l: "", e: [], dp: [], c: "", sz: 0, g: [] }) }
        for (var j = 0; j < own.length; j++) if (pac.explicit.indexOf(own[j]) < 0 && pac.all[own[j]] !== undefined) { var o = idx["pacman:" + own[j]]; out.push(o ? o : { s: "aur", n: own[j], d: "", v: pac.all[own[j]] || "", h: "", l: "", e: [], dp: [], c: "", sz: 0, g: [] }) }
        for (var k = 0; k < brew.leaves.length; k++) { var b = idx["brew:" + brew.leaves[k]]; out.push(b ? b : { s: "brew", n: brew.leaves[k], d: "", v: brew.all[brew.leaves[k]] || "", h: "", l: "", e: [], dp: [], c: "", sz: 0, g: [] }) }
        return sortList(out.filter(function (e) { return srcFilter === "all" || e.s === srcFilter }))
    }
    readonly property var updateApps: {
        var out = []
        for (var n in pac.outdated) { var e = idx["pacman:" + n]; out.push(e ? e : { s: "pacman", n: n, d: "", v: "", h: "", l: "", e: [], dp: [], c: "", sz: 0, g: [] }) }
        for (var m in brew.outdated) { var b = idx["brew:" + m]; out.push(b ? b : { s: "brew", n: m, d: "", v: "", h: "", l: "", e: [], dp: [], c: "", sz: 0, g: [] }) }
        return out.filter(function (e) { return srcFilter === "all" || e.s === srcFilter })
    }
    readonly property var hero: {
        var pool = ["firefox", "vlc", "gimp", "btop", "inkscape", "mpv", "krita", "obs-studio", "yazi", "zellij"]
        var day = Math.floor(Date.now() / 86400000)
        for (var k = 0; k < pool.length; k++) { var l = byName[pool[(day + k) % pool.length]]; if (l && l.length) return l[0] }
        return topApps.length ? topApps[0] : null
    }
    readonly property var viewEntry: {
        if (viewKey === "") return null
        var e = idx[viewKey]
        if (e) return e
        for (var i = 0; i < aurRes.length; i++) if (key(aurRes[i]) === viewKey) return aurRes[i]
        var p = viewKey.split(":")
        return { s: p[0], n: p.slice(1).join(":"), d: "", v: "", h: "", l: "", e: [], dp: [], c: "", sz: 0, g: [] }
    }

    // ---- loading ----
    function ingest() {
        var m = {}, bn = {}, all = [pacCat, brewCat]
        for (var k = 0; k < all.length; k++) for (var i = 0; i < all[k].length; i++) { var e = all[k][i]; m[e.s + ":" + e.n] = e; (bn[e.n] = bn[e.n] || []).push(e) }
        idx = m; byName = bn
        var r = {}
        for (var a = 0; a < pacTop.length; a++) r["pacman:" + pacTop[a]] = a
        for (var b = 0; b < brewTop.length; b++) r["brew:" + brewTop[b]] = b
        topRank = r
    }
    Process { id: pcP; command: ["/usr/local/bin/smof-pkg", "catalog", "pacman"]
        stdout: StdioCollector { onStreamFinished: { try { win.pacCat = JSON.parse(text) } catch (e) {} win.loaded++; win.ingest() } } }
    Process { id: bcP; command: ["/usr/local/bin/smof-pkg", "catalog", "brew"]
        stdout: StdioCollector { onStreamFinished: { try { win.brewCat = JSON.parse(text) } catch (e) {} win.loaded++; win.ingest() } } }
    Process { id: ptP; command: ["/usr/local/bin/smof-pkg", "top", "pacman"]
        stdout: StdioCollector { onStreamFinished: { try { win.pacTop = JSON.parse(text) } catch (e) {} win.ingest() } } }
    Process { id: btP; command: ["/usr/local/bin/smof-pkg", "top", "brew"]
        stdout: StdioCollector { onStreamFinished: { try { win.brewTop = JSON.parse(text) } catch (e) {} win.ingest() } } }
    Process { id: stP; command: ["/usr/local/bin/smof-pkg", "state"]
        stdout: StdioCollector { onStreamFinished: { try { var o = JSON.parse(text); win.pac = o.pacman; win.brew = o.brew; win.own = o.own; win.free = o.free; win.brewOk = o.brewok } catch (e) {} } } }
    function loadState() { stP.running = true }
    Component.onCompleted: { pcP.running = true; bcP.running = true; ptP.running = true; btP.running = true; stP.running = true }

    // AUR search, a moment after the typing stops
    Process { id: aurP
        stdout: StdioCollector { onStreamFinished: { win.aurBusy = false; try { var o = JSON.parse(text); win.aurRes = o.results || []; win.aurErr = o.error || "" } catch (e) {} } } }
    Timer { id: aurT; interval: 550; onTriggered: {
        var q = win.query.trim()
        if (q.length < 2 || win.srcFilter === "pacman" || win.srcFilter === "brew") { win.aurRes = []; return }
        win.aurBusy = true; aurP.command = ["/usr/local/bin/smof-pkg", "aur-search", q]; aurP.running = true } }
    function setQuery(q) { sbox.text = q }
    Process { id: archP
        stdout: StdioCollector { onStreamFinished: { try { win.aurArch = JSON.parse(text) } catch (e) { win.aurArch = { ok: false } } } } }

    // ---- jobs: started in the background, so closing this window does not stop them ----
    function enqueue(src, action, name) {
        for (var i = 0; i < active.length; i++) if (active[i].src === src && active[i].n === name && active[i].action === action) return
        Quickshell.execDetached({ command: ["/usr/local/bin/smof-pkg", "start", src, action, name], workingDirectory: Quickshell.env("HOME") })
        pollT.interval = 300; pollT.restart()
    }
    function stopJob(id) { Quickshell.execDetached({ command: ["/usr/local/bin/smof-pkg", "kill", id], workingDirectory: Quickshell.env("HOME") }); pollT.interval = 800; pollT.restart() }
    function dismissJob(id) { Quickshell.execDetached({ command: ["/usr/local/bin/smof-pkg", "dismiss", id], workingDirectory: Quickshell.env("HOME") }) }
    Process { id: jobsP; command: ["/usr/local/bin/smof-pkg", "jobs"]
        stdout: StdioCollector { onStreamFinished: { try { win.takeJobs(JSON.parse(text)) } catch (e) {} } } }
    Timer { id: pollT; interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { interval = win.active.length > 0 || win.logOpen ? 1000 : 3000; if (!jobsP.running) jobsP.running = true } }
    // what went wrong, in words a person can act on
    function friendly(line) {
        var l = line || ""
        if (/temporarily locked|locked out/i.test(l)) return "Too many wrong passwords. Wait ten minutes and try again"
        if (/incorrect password|try again|authentication failure/i.test(l)) return "The password was wrong"
        if (/terminal is required|askpass/i.test(l)) return "The permission window could not open"
        if (/no space left|not enough room/i.test(l)) return "The disk is full, free some room first"
        if (/could not lock database|database is locked/i.test(l)) return "Another installation is running, try again in a minute"
        if (/failed retrieving|could not resolve|failed to connect|connection (timed out|refused)|unable to connect/i.test(l)) return "No connection to download from, check the network"
        if (/updates waiting|update it first/i.test(l)) return "The system has updates waiting, update it first"
        if (/target not found|was not found/i.test(l)) return "This package is not in the list any more, refresh the list"
        return l.replace(/^Error:\s*/i, "")
    }
    function takeJobs(list) {
        var any = false
        for (var i = 0; i < list.length; i++) {
            var j = list[i]
            if (j.status === "queued" || j.status === "running") { readLine(j.line || "", j.id); continue }
            if (reported[j.id]) continue
            var r = Object.assign({}, reported); r[j.id] = true; reported = r
            dismissJob(j.id)
            if (j.status === "cancelled") { any = true; continue }
            var what = j.n !== "" ? pretty(j.n) : (j.src === "pacman" ? "the system" : "everything")
            var ok = j.status === "done"
            var verb = j.action === "install" ? "Installed " : (j.action === "uninstall" ? "Removed " : "Updated ")
            note = ok ? verb + what : "Could not " + (j.action === "uninstall" ? "remove " : (j.action === "install" ? "install " : "update ")) + what + (j.line ? ": " + friendly(j.line) : "")
            noteKind = ok ? "ok" : "error"; any = true
            Ui.sound(ok ? "success" : "error")
        }
        jobsList = list
        if (any) loadState()
    }
    Process { id: logP
        stdout: StdioCollector { onStreamFinished: { try { win.logLines = JSON.parse(text) } catch (e) {} } } }
    Timer { interval: 1200; running: win.logOpen && win.cur !== null; repeat: true; triggeredOnStart: true
        onTriggered: { if (!logP.running && win.cur) { logP.command = ["/usr/local/bin/smof-pkg", "log", win.cur.id]; logP.running = true } } }

    Timer { id: noteT; interval: 6000; running: win.note !== "" && win.cur === null; onTriggered: win.note = "" }

    function open(e) {
        var d = DesktopEntries.heuristicLookup(e.n)
        if (d) { d.execute(); return }
        var exe = (e.e && e.e.length) ? e.e[0] : e.n
        Quickshell.execDetached({ command: ["foot", "-e", "bash", "-lc", exe + "; echo; printf 'Press Enter to close '; read x"], workingDirectory: Quickshell.env("HOME") })
    }
    function blocked(e) { return e.s !== "brew" && pacOutCount > 0 && !isInst(e) }
    function noRoom(e) { return e.s === "pacman" && e.sz > 0 && free > 0 && e.sz > free - 300 * 1048576 && !isInst(e) }
    function press(e) {
        if (jobOf(e)) return
        if (isOut(e)) { if (e.s === "brew") enqueue("brew", "update", e.n); else go("updates"); return }
        if (!isInst(e)) {
            if (blocked(e)) { go("updates"); return }
            if (noRoom(e)) { note = "Not enough room on the disk for " + pretty(e.n); noteKind = "error"; return }
            if (e.s === "aur") { aurArch = null; archP.command = ["/usr/local/bin/smof-pkg", "aur-arch", e.n]; archP.running = true; confirm = e; return }
            enqueue(e.s, "install", e.n)
        } else open(e)
    }
    function go(p) { viewKey = ""; page = p; if (p !== "search") { query = ""; sbox.text = "" } }
    function updateAll() { if (pacOutCount > 0) enqueue("pacman", "update", ""); if (brewOutCount > 0) enqueue("brew", "update", "") }

    // ---- building blocks ----
    component Tile: Rectangle {
        id: tl
        property string n: ""
        property int size: 56
        width: size; height: size; radius: size * 0.28
        color: win.tileBg(n)
        T { anchors.centerIn: parent; text: tl.n.charAt(0).toUpperCase(); font.pixelSize: tl.size * 0.46; w: 700; color: win.tileFg(tl.n) }
    }
    component Spin: Item {
        id: sp
        property color col: Theme.acc
        width: 18; height: 18
        Canvas {
            anchors.fill: parent
            onPaint: { var c = getContext("2d"); c.reset(); c.lineWidth = 2.4; c.strokeStyle = sp.col; c.lineCap = "round"; c.beginPath(); c.arc(9, 9, 6.5, 0, 4.4); c.stroke() }
            onVisibleChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }
        RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: sp.visible }
    }
    component Badge: Rectangle {
        property string s: "pacman"
        height: 18; width: bt.implicitWidth + 12; radius: 9
        color: Qt.hsla(win.srcTint(s), Theme.dark ? 0.5 : 0.6, Theme.dark ? 0.28 : 0.86, 1)
        T { id: bt; anchors.centerIn: parent; text: win.srcName(parent.s).toUpperCase(); font.pixelSize: 10; w: 700; font.letterSpacing: 0.6; color: Qt.hsla(win.srcTint(parent.s), Theme.dark ? 0.7 : 0.6, Theme.dark ? 0.8 : 0.32, 1) }
    }
    component Chip: Item {
        id: cp
        property string label: ""
        property bool on: false
        property color tint: Theme.acc
        signal clicked()
        height: 34; width: ct.implicitWidth + 28
        Rectangle { anchors.fill: parent; radius: 17; color: cp.on ? cp.tint : "transparent"; border.color: cp.on ? "transparent" : Theme.i12; border.width: 1.5
            Rectangle { anchors.fill: parent; radius: 17; color: Theme.ink; opacity: !cp.on && cma.containsMouse ? .07 : 0 } }
        T { id: ct; anchors.centerIn: parent; text: cp.label; font.pixelSize: 14; w: cp.on ? 650 : 480; color: cp.on ? Theme.onacc : Theme.ink }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: cp.clicked() }
    }
    // the Get button
    component GetBtn: Item {
        id: gb
        property var e: null
        property bool big: false
        readonly property var j: e ? win.jobOf(e) : null
        readonly property bool inst: e ? win.isInst(e) : false
        readonly property bool out: e ? win.isOut(e) : false
        readonly property bool blk: e ? win.blocked(e) : false
        readonly property bool room: e ? win.noRoom(e) : false
        readonly property string label: j ? (win.isCur(e) ? (win.cur.action === "uninstall" ? "Removing" : (win.cur.action === "update" ? "Updating" : "Installing")) : "Waiting")
            : (out ? "Update" : (inst ? "Open" : (blk ? "Update first" : (room ? "No room" : "Get"))))
        readonly property bool filled: (!j && !inst && !blk && !room) || out
        width: Math.max(big ? 120 : 86, lt.implicitWidth + (j ? 54 : 36)); height: big ? 42 : 34
        opacity: room ? .55 : 1
        Rectangle { anchors.fill: parent; radius: height / 2; color: gb.filled ? Theme.acc : Theme.moonbg
            Rectangle { anchors.fill: parent; radius: parent.radius; color: gb.filled ? "#000000" : Theme.acc; opacity: gma.pressed ? .18 : (gma.containsMouse ? (gb.filled ? .10 : .12) : 0); Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } } } }
        Row { anchors.centerIn: parent; spacing: 8
            Spin { visible: !!gb.j; anchors.verticalCenter: parent.verticalCenter; col: gb.filled ? Theme.onacc : Theme.acc }
            T { id: lt; anchors.verticalCenter: parent.verticalCenter; text: gb.label; font.pixelSize: gb.big ? 17 : 15; w: 650; color: gb.filled ? Theme.onacc : Theme.acc } }
        MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; enabled: !gb.j && !gb.room; onClicked: win.press(gb.e) }
    }
    component AppRow: Item {
        id: ar
        property var e: null
        property int rank: 0
        width: parent ? parent.width : 400; height: 78
        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 20; color: Theme.acc; opacity: arma.containsMouse ? .08 : 0; Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } } }
        T { visible: ar.rank > 0; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 26; horizontalAlignment: Text.AlignHCenter; text: ar.rank; font.pixelSize: 18; w: 600; color: Theme.i55 }
        Tile { id: art; x: ar.rank > 0 ? 44 : 12; anchors.verticalCenter: parent.verticalCenter; n: ar.e ? ar.e.n : ""; size: 54 }
        Column { x: art.x + 66; anchors.verticalCenter: parent.verticalCenter; width: parent.width - art.x - 66 - gbtn.width - 24; spacing: 2
            Row { spacing: 8
                T { id: nm; text: ar.e ? win.pretty(ar.e.n) : ""; font.pixelSize: 17; w: 600; width: Math.min(implicitWidth, ar.width - 300); elide: Text.ElideRight }
                Badge { anchors.verticalCenter: parent.verticalCenter; s: ar.e ? ar.e.s : "pacman" } }
            T { width: parent.width; elide: Text.ElideRight; font.pixelSize: 14; color: Theme.i62
                text: ar.e ? (win.isOut(ar.e) ? win.outInfo(ar.e).from + "  to  " + win.outInfo(ar.e).to : (ar.e.d + (ar.e.sz ? "   " + win.fmtSize(ar.e.sz) : "") + (ar.e.s === "aur" && ar.e.votes !== undefined ? "   " + ar.e.votes + " votes" : ""))) : "" } }
        GetBtn { id: gbtn; e: ar.e; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter }
        MouseArea { id: arma; anchors.fill: parent; hoverEnabled: true; z: -1; onClicked: win.viewKey = win.key(ar.e) }
    }
    component Section: Item {
        id: sc
        property string title: ""
        property string more: ""
        signal moreClicked()
        width: parent ? parent.width : 400; height: 40
        T { anchors.verticalCenter: parent.verticalCenter; text: sc.title; font.pixelSize: 22; w: 650 }
        Item { visible: sc.more !== ""; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: mt.implicitWidth + 20; height: 30
            T { id: mt; anchors.centerIn: parent; text: sc.more; font.pixelSize: 15; w: 560; color: Theme.acc }
            MouseArea { anchors.fill: parent; onClicked: sc.moreClicked() } }
    }

    // ---- sidebar ----
    Rectangle {
        id: side
        width: win.compact ? 64 : (win.width < 940 ? 206 : 244); height: parent.height
        color: Theme.sidebg
        Column {
            x: 12; y: 18; width: parent.width - 24; spacing: 3
            Row { x: win.compact ? 4 : 10; spacing: 10; height: 40
                Rectangle { width: 34; height: 34; radius: 11; color: Theme.acc; anchors.verticalCenter: parent.verticalCenter
                    T { anchors.centerIn: parent; text: "S"; font.pixelSize: 20; w: 700; color: Theme.onacc } }
                T { visible: !win.compact; anchors.verticalCenter: parent.verticalCenter; text: "Smof Store"; font.pixelSize: 20; w: 650 } }
            Item { width: 1; height: 12 }
            Repeater {
                model: [ { id: "discover", name: "Discover" }, { id: "installed", name: "Installed" }, { id: "updates", name: "Updates" } ]
                Item {
                    required property var modelData
                    width: parent.width; height: 44
                    readonly property bool cur: win.viewKey === "" && win.page === modelData.id
                    Rectangle { anchors.fill: parent; radius: 16; color: Theme.acc; opacity: cur ? 1 : (sma.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } } }
                    T { x: win.compact ? 0 : 16; width: win.compact ? parent.width : implicitWidth; horizontalAlignment: win.compact ? Text.AlignHCenter : Text.AlignLeft; anchors.verticalCenter: parent.verticalCenter; text: win.compact ? modelData.name.charAt(0) : modelData.name; font.pixelSize: 17; w: cur ? 650 : 480; color: cur ? Theme.onacc : Theme.ink }
                    Rectangle { visible: modelData.id === "updates" && win.outCount > 0 && !win.compact; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(22, ub.implicitWidth + 12); height: 22; radius: 11; color: cur ? Theme.onacc : Theme.acc
                        T { id: ub; anchors.centerIn: parent; text: win.outCount; font.pixelSize: 13; w: 650; color: cur ? Theme.acc : Theme.onacc } }
                    MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(modelData.id) }
                }
            }
            Item { width: 1; height: 14 }
            T { visible: !win.compact; x: 12; text: "Categories"; font.pixelSize: 13; w: 600; color: Theme.i55 }
            Repeater {
                model: win.cats
                Item {
                    required property var modelData
                    width: parent.width; height: 42
                    readonly property bool cur: win.viewKey === "" && win.page === "cat:" + modelData.id
                    Rectangle { anchors.fill: parent; radius: 16; color: Theme.acc; opacity: cur ? 1 : (cma2.containsMouse ? .12 : 0); Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] } } }
                    Rectangle { x: win.compact ? (parent.width - 12) / 2 : 14; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: Qt.hsla(modelData.tint, Theme.dark ? 0.65 : 0.55, Theme.dark ? 0.7 : 0.5, 1); border.color: cur ? Theme.onacc : "transparent"; border.width: 2 }
                    T { visible: !win.compact; x: 38; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 46; elide: Text.ElideRight; text: modelData.name; font.pixelSize: 16; w: cur ? 650 : 480; color: cur ? Theme.onacc : Theme.ink }
                    MouseArea { id: cma2; anchors.fill: parent; hoverEnabled: true; onClicked: win.go("cat:" + modelData.id) }
                }
            }
        }
    }

    // ---- top: title, search, filters ----
    Item {
        id: top
        x: side.width; width: parent.width - side.width; height: win.viewKey === "" ? 66 + filt.implicitHeight + 12 : 66
        Item { visible: win.viewKey !== ""; x: 14; y: 13; width: 40; height: 40
            Rectangle { anchors.fill: parent; radius: 20; color: Theme.ink; opacity: bma.containsMouse ? .12 : 0 }
            T { anchors.centerIn: parent; text: "‹"; font.pixelSize: 28; w: 500 }
            MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; onClicked: win.viewKey = "" } }
        T { visible: win.viewKey === ""; x: 24; y: 16; font.pixelSize: win.compact ? 24 : 28; w: 700
            text: win.page === "discover" ? "Discover" : (win.page === "installed" ? "Installed" : (win.page === "updates" ? "Updates" : (win.page === "search" ? "Search" : (win.catById(win.page.slice(4)) ? win.catById(win.page.slice(4)).name : "")))) }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 20; y: 11
            width: Math.max(130, Math.min(360, parent.width - 210)); height: 44; radius: 22; color: Theme.cardbg
            T { visible: sbox.text === ""; x: 18; anchors.verticalCenter: parent.verticalCenter; text: "Search all sources"; font.pixelSize: 16; color: Theme.i5 }
            TextInput { id: sbox; x: 18; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter; font.family: "Google Sans Flex"; font.pixelSize: 16; color: Theme.ink; clip: true
                onTextChanged: { win.query = text; if (text !== "") { win.viewKey = ""; win.page = "search"; aurT.restart() } else { win.aurRes = []; if (win.page === "search") win.page = "discover" } } }
        }
        // filters
        Flow {
            id: filt
            visible: win.viewKey === ""
            x: 24; y: 66; width: parent.width - 48; spacing: 8
            Chip { label: "All sources"; on: win.srcFilter === "all"; onClicked: { win.srcFilter = "all"; aurT.restart() } }
            Chip { label: "Pacman"; on: win.srcFilter === "pacman"; tint: Qt.hsla(0.6, 0.55, 0.45, 1); onClicked: { win.srcFilter = "pacman"; aurT.restart() } }
            Chip { label: "Homebrew"; on: win.srcFilter === "brew"; tint: Qt.hsla(0.09, 0.7, 0.42, 1); onClicked: { win.srcFilter = "brew"; aurT.restart() } }
            Chip { label: "AUR"; on: win.srcFilter === "aur"; tint: Qt.hsla(0.8, 0.5, 0.45, 1); onClicked: { win.srcFilter = "aur"; aurT.restart() } }
            Item { width: 14; height: 1 }
            Chip { label: "Installed"; on: win.showFilter === "installed"; onClicked: win.showFilter = win.showFilter === "installed" ? "all" : "installed" }
            Chip { label: "Not installed"; on: win.showFilter === "new"; onClicked: win.showFilter = win.showFilter === "new" ? "all" : "new" }
            Item { width: 14; height: 1 }
            Chip { label: "Sort: " + (win.sortBy === "relevance" ? "Best match" : (win.sortBy === "name" ? "Name" : (win.sortBy === "size" ? "Size" : "Popular")))
                onClicked: win.sortBy = win.sortBy === "relevance" ? "popular" : (win.sortBy === "popular" ? "name" : (win.sortBy === "name" ? "size" : "relevance")) }
        }
    }

    // ---- pages ----
    Item {
        id: body
        x: side.width; y: top.height; width: parent.width - side.width; height: parent.height - top.height

        Column { visible: !win.ready; anchors.centerIn: parent; spacing: 14
            Spin { anchors.horizontalCenter: parent.horizontalCenter; width: 28; height: 28 }
            T { anchors.horizontalCenter: parent.horizontalCenter; text: "Opening the shelves..."; font.pixelSize: 18; color: Theme.i55 } }

        Flickable {

            SmoothWheel {}
            id: fl
            visible: win.ready && win.viewKey === ""
            anchors.fill: parent
            contentHeight: pg.implicitHeight + 100
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: pg
                x: 24; width: fl.width - 48; spacing: 14

                // a notice about waiting system updates
                Rectangle {
                    visible: win.pacOutCount > 0 && win.page !== "updates"
                    width: parent.width; height: 54; radius: 18; color: Theme.warnbg
                    T { x: 18; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 170; elide: Text.ElideRight; text: "The system has " + win.pacOutCount + " updates waiting. Update it before installing from Pacman or the AUR."; font.pixelSize: 15; color: Theme.warnfg }
                    Item { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: wt.implicitWidth + 28; height: 34
                        Rectangle { anchors.fill: parent; radius: 17; color: Theme.warnfg }
                        T { id: wt; anchors.centerIn: parent; text: "Update now"; font.pixelSize: 14; w: 650; color: Theme.warnbg }
                        MouseArea { anchors.fill: parent; onClicked: win.go("updates") } } }

                // Discover
                Column { visible: win.page === "discover"; width: parent.width; spacing: 14
                    Rectangle {
                        visible: !!win.hero
                        width: parent.width; height: pg.width < 560 ? 200 : 230; radius: 36; clip: true
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: win.hero ? Qt.hsla(win.hue(win.hero.n), Theme.dark ? 0.5 : 0.6, Theme.dark ? 0.28 : 0.72, 1) : "#888" }
                            GradientStop { position: 1; color: win.hero ? Qt.hsla((win.hue(win.hero.n) + 0.12) % 1, Theme.dark ? 0.5 : 0.65, Theme.dark ? 0.18 : 0.82, 1) : "#444" } }
                        MouseArea { anchors.fill: parent; onClicked: if (win.hero) win.viewKey = win.key(win.hero) }
                        Column { x: pg.width < 560 ? 24 : 36; anchors.verticalCenter: parent.verticalCenter; width: parent.width - (pg.width < 560 ? 48 : (pg.width < 700 ? 60 : 330)); spacing: 8
                            T { text: "APP OF THE DAY"; font.pixelSize: 13; w: 700; color: Theme.i62; font.letterSpacing: 1.5 }
                            T { text: win.hero ? win.pretty(win.hero.n) : ""; font.pixelSize: pg.width < 560 ? 32 : 44; w: 700; width: parent.width; elide: Text.ElideRight }
                            T { text: win.hero ? win.hero.d : ""; font.pixelSize: 17; color: Theme.i62; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                            Item { width: 1; height: 6 }
                            GetBtn { e: win.hero; big: true } }
                        Tile { visible: pg.width >= 700; anchors.right: parent.right; anchors.rightMargin: 56; anchors.verticalCenter: parent.verticalCenter; n: win.hero ? win.hero.n : ""; size: 150 }
                    }
                    Section { title: "Top charts"; more: "" }
                    Flow { width: parent.width; spacing: 8
                        Repeater { model: win.topApps
                            AppRow { required property var modelData; required property int index; e: modelData; rank: index + 1; width: Math.floor((pg.width - 8) / (pg.width > 920 ? 2 : 1)) } } }
                    Repeater {
                        model: win.cats
                        Column {
                            required property var modelData
                            readonly property var items: win.listOfCat(modelData)
                            visible: items.length > 0
                            width: pg.width; spacing: 6
                            Section { title: modelData.name; more: "See all"; onMoreClicked: win.go("cat:" + modelData.id) }
                            Flow { width: parent.width; spacing: 8
                                Repeater { model: parent.parent.items.slice(0, 4)
                                    AppRow { required property var modelData; e: modelData; width: Math.floor((pg.width - 8) / (pg.width > 920 ? 2 : 1)) } } }
                        }
                    }
                }

                // a category
                Column { visible: win.page.indexOf("cat:") === 0; width: parent.width; spacing: 6
                    Repeater { model: win.page.indexOf("cat:") === 0 && win.catById(win.page.slice(4)) ? win.listOfCat(win.catById(win.page.slice(4))) : []
                        AppRow { required property var modelData; e: modelData } } }

                // installed
                Column { visible: win.page === "installed"; width: parent.width; spacing: 6
                    T { visible: win.installedApps.length === 0; text: "Nothing here yet."; font.pixelSize: 17; color: Theme.i55 }
                    Repeater { model: win.installedApps; AppRow { required property var modelData; e: modelData } } }

                // updates
                Column { visible: win.page === "updates"; width: parent.width; spacing: 6
                    Item { width: parent.width; height: 52
                        T { anchors.verticalCenter: parent.verticalCenter; text: win.outCount === 0 ? "Everything is up to date." : win.outCount + (win.outCount === 1 ? " update available" : " updates available"); font.pixelSize: 17; color: Theme.i62 }
                        Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            Item { width: ckt.implicitWidth + 36; height: 38
                                Rectangle { anchors.fill: parent; radius: 19; color: Theme.moonbg; Rectangle { anchors.fill: parent; radius: 19; color: Theme.acc; opacity: ckma.containsMouse ? .14 : 0 } }
                                T { id: ckt; anchors.centerIn: parent; text: "Check now"; font.pixelSize: 15; w: 650; color: Theme.acc }
                                MouseArea { id: ckma; anchors.fill: parent; hoverEnabled: true; onClicked: win.enqueue("pacman", "refresh", "") } }
                            Item { visible: win.outCount > 0; width: uat.implicitWidth + 40; height: 38
                                Rectangle { anchors.fill: parent; radius: 19; color: Theme.acc; Rectangle { anchors.fill: parent; radius: 19; color: "#000000"; opacity: uma.pressed ? .18 : 0 } }
                                T { id: uat; anchors.centerIn: parent; text: "Update all"; font.pixelSize: 15; w: 650; color: Theme.onacc }
                                MouseArea { id: uma; anchors.fill: parent; onClicked: win.updateAll() } } } }
                    T { visible: win.pacOutCount > 0; text: "System updates (Pacman) are installed all together, that is how Arch stays safe."; font.pixelSize: 14; color: Theme.i55 }
                    Repeater { model: win.updateApps; AppRow { required property var modelData; e: modelData } } }

                // search
                Column { visible: win.page === "search"; width: parent.width; spacing: 6
                    T { visible: win.results.length === 0 && win.aurShown.length === 0 && !win.aurBusy; text: "Nothing matches \"" + win.query + "\""; font.pixelSize: 17; color: Theme.i55 }
                    Repeater { model: win.results; AppRow { required property var modelData; e: modelData } }
                    Item { visible: win.srcFilter !== "pacman" && win.srcFilter !== "brew" && win.query.trim().length >= 2; width: parent.width; height: 48
                        Row { anchors.verticalCenter: parent.verticalCenter; spacing: 10
                            T { text: "From the AUR"; font.pixelSize: 20; w: 650; anchors.verticalCenter: parent.verticalCenter }
                            Spin { visible: win.aurBusy; anchors.verticalCenter: parent.verticalCenter }
                            T { visible: win.aurErr !== ""; text: win.aurErr; font.pixelSize: 14; color: Theme.errfg; anchors.verticalCenter: parent.verticalCenter } } }
                    Repeater { model: win.aurShown; AppRow { required property var modelData; e: modelData } } }
            }
        }

        // ---- the page of one app ----
        Flickable {
            SmoothWheel {}
            id: dfl
            visible: win.ready && win.viewKey !== ""
            anchors.fill: parent
            contentHeight: dcol.implicitHeight + 100
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property var e: win.viewEntry
            readonly property var also: { var o = []; if (e) { var l = win.byName[e.n] || []; for (var i = 0; i < l.length; i++) if (l[i].s !== e.s) o.push(l[i]) } return o }
            Column {
                id: dcol
                x: 28; width: dfl.width - 56; spacing: 22
                Row { spacing: 22; width: parent.width
                    Tile { n: dfl.e ? dfl.e.n : ""; size: dcol.width < 520 ? 72 : 116 }
                    Column { width: parent.width - (dcol.width < 520 ? 94 : 138); anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Row { spacing: 10
                            T { text: dfl.e ? win.pretty(dfl.e.n) : ""; font.pixelSize: dcol.width < 520 ? 26 : 34; w: 700; width: Math.min(implicitWidth, dcol.width - 300); elide: Text.ElideRight }
                            Badge { anchors.verticalCenter: parent.verticalCenter; s: dfl.e ? dfl.e.s : "pacman" } }
                        T { text: dfl.e ? dfl.e.d : ""; font.pixelSize: 17; color: Theme.i62; width: parent.width; wrapMode: Text.Wrap }
                        Row { spacing: 10; topPadding: 8
                            GetBtn { e: dfl.e; big: true }
                            Item { visible: !!dfl.e && win.isInst(dfl.e) && win.canRemove(dfl.e) && !win.jobOf(dfl.e); width: rmt.implicitWidth + 40; height: 42
                                Rectangle { anchors.fill: parent; radius: 21; color: Theme.errbg; Rectangle { anchors.fill: parent; radius: 21; color: Theme.errfg; opacity: rma.containsMouse ? .14 : 0 } }
                                T { id: rmt; anchors.centerIn: parent; text: "Remove"; font.pixelSize: 17; w: 650; color: Theme.errfg }
                                MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; onClicked: win.enqueue(dfl.e.s, "uninstall", dfl.e.n) } }
                            T { visible: !!dfl.e && win.isInst(dfl.e) && !win.canRemove(dfl.e); anchors.verticalCenter: parent.verticalCenter; text: "Part of the system, the store keeps it"; font.pixelSize: 14; color: Theme.i55 } } }
                }
                // other sources
                Row { visible: dfl.also.length > 0; spacing: 8
                    T { anchors.verticalCenter: parent.verticalCenter; text: "Also from"; font.pixelSize: 15; color: Theme.i55 }
                    Repeater { model: dfl.also; Chip { required property var modelData; label: win.srcName(modelData.s) + "  " + modelData.v; onClicked: win.viewKey = win.key(modelData) } } }
                // AUR warning
                Rectangle { visible: !!dfl.e && dfl.e.s === "aur"; width: parent.width; height: aw.implicitHeight + 28; radius: 20; color: Theme.warnbg
                    T { id: aw; x: 18; y: 14; width: parent.width - 36; wrapMode: Text.Wrap; font.pixelSize: 15; color: Theme.warnfg
                        text: "The AUR holds recipes written by users, nobody checks them. Installing builds the program on this computer by running the recipe." + (dfl.e && dfl.e.ood ? " This one is marked out of date." : "") } }
                // facts
                Rectangle { width: parent.width; height: dcol.width < 520 ? 176 : 96; radius: 26; color: Theme.cardbg
                    Flow { anchors.fill: parent
                        Repeater {
                            model: dfl.e ? [ ["VERSION", dfl.e.v || (dfl.e.s === "brew" ? (win.brew.all[dfl.e.n] || "-") : (win.pac.all[dfl.e.n] || "-"))],
                                             [dfl.e.s === "aur" ? "VOTES" : "SIZE", dfl.e.s === "aur" ? String(dfl.e.votes || 0) : (dfl.e.sz ? win.fmtSize(dfl.e.sz) : "-")],
                                             ["LICENSE", dfl.e.l || "-"],
                                             ["STATE", win.isOut(dfl.e) ? "Update ready" : (win.isInst(dfl.e) ? "Installed" : "Not installed")] ] : []
                            Item { required property var modelData; width: dcol.width < 520 ? dcol.width / 2 : dcol.width / 4; height: dcol.width < 520 ? 88 : 96
                                Column { anchors.centerIn: parent; spacing: 6; width: parent.width - 20
                                    T { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData[0]; font.pixelSize: 12; w: 700; color: Theme.i55; font.letterSpacing: 1 }
                                    T { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData[1]; font.pixelSize: 17; w: 600 } } } } } }
                Column { visible: !!dfl.e && dfl.e.e.length > 0; width: parent.width; spacing: 8
                    T { text: "Commands"; font.pixelSize: 20; w: 650 }
                    Flow { width: parent.width; spacing: 8
                        Repeater { model: dfl.e ? dfl.e.e : []
                            Rectangle { required property string modelData; height: 34; width: ct2.implicitWidth + 28; radius: 17; color: Theme.moonbg
                                T { id: ct2; anchors.centerIn: parent; text: modelData; font.pixelSize: 15; font.family: "monospace"; color: Theme.acc } } } } }
                Column { visible: !!dfl.e && dfl.e.dp.length > 0; width: parent.width; spacing: 8
                    T { text: "Comes with"; font.pixelSize: 20; w: 650 }
                    Flow { width: parent.width; spacing: 8
                        Repeater { model: dfl.e ? dfl.e.dp.slice(0, 24) : []
                            Rectangle { required property string modelData; height: 34; width: dt2.implicitWidth + 28; radius: 17; color: Theme.i12
                                T { id: dt2; anchors.centerIn: parent; text: modelData; font.pixelSize: 15 } } } } }
                Column { visible: !!dfl.e && dfl.e.c !== ""; width: parent.width; spacing: 8
                    T { text: "Good to know"; font.pixelSize: 20; w: 650 }
                    T { text: dfl.e ? dfl.e.c : ""; font.pixelSize: 15; color: Theme.i62; width: parent.width; wrapMode: Text.Wrap } }
                Column { visible: !!dfl.e && dfl.e.h !== ""; width: parent.width; spacing: 6
                    T { text: "Website"; font.pixelSize: 20; w: 650 }
                    T { text: dfl.e ? dfl.e.h : ""; font.pixelSize: 15; color: Theme.acc; width: parent.width; wrapMode: Text.WrapAnywhere } }
            }
        }
    }

    // ---- what is happening now ----
    Rectangle {
        visible: win.cur !== null || win.note !== ""
        x: body.x + (body.width - width) / 2; y: parent.height - height - 22
        width: Math.min(560, body.width - 48); height: win.cur !== null ? 74 : 58; radius: 29
        color: Theme.menubg; border.color: win.noteKind === "error" && win.cur === null ? Theme.errfg : Theme.glassBorder; border.width: win.noteKind === "error" && win.cur === null ? 2 : 1
        MouseArea { anchors.fill: parent; enabled: win.cur !== null; cursorShape: Qt.PointingHandCursor; onClicked: win.logOpen = true }
        Row { x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 12; width: parent.width - 40
            Spin { visible: win.cur !== null; anchors.verticalCenter: parent.verticalCenter }
            Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - (win.cur !== null ? 30 : 0); spacing: 1
                T { width: parent.width; elide: Text.ElideRight; font.pixelSize: 16; w: 600
                    text: win.cur ? ((win.cur.action === "install" ? "Installing " : (win.cur.action === "uninstall" ? "Removing " : "Updating ")) + (win.cur.n !== "" ? win.pretty(win.cur.n) : (win.cur.src === "pacman" ? "the system" : "everything")) + "  from " + win.srcName(win.cur.src)) + (win.queue.length > 0 ? "  and " + win.queue.length + " more" : "") : win.note }
                T { visible: win.cur !== null; width: parent.width; elide: Text.ElideRight; font.pixelSize: 13; color: Theme.i55
                    text: win.stage + (win.prog >= 0 ? "  " + Math.round(win.prog * 100) + "%" : "") }
                Item { visible: win.cur !== null; width: parent.width; height: 8
                    Rectangle { anchors.fill: parent; radius: 4; color: Theme.i12; clip: true
                        Rectangle { visible: win.prog >= 0; height: parent.height; radius: 4; color: Theme.acc; width: parent.width * win.prog; Behavior on width { NumberAnimation { duration: 375; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] } } }
                        Rectangle { id: slide; visible: win.prog < 0; width: parent.width * 0.3; height: parent.height; radius: 4; color: Theme.acc
                            SequentialAnimation on x { running: slide.visible && win.cur !== null; loops: Animation.Infinite
                                NumberAnimation { from: -slide.width; to: slide.parent.width; duration: 1100; easing.type: Easing.InOutSine } } } } } } }
    }

    // ---- the log and the stop button ----
    Item {
        visible: win.logOpen
        anchors.fill: parent
        MouseArea { anchors.fill: parent; onClicked: win.logOpen = false }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: .4 }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(640, win.width - 40); height: Math.min(520, win.height - 60); radius: 30; color: Theme.menubg; border.color: Theme.glassBorder
            MouseArea { anchors.fill: parent }
            T { id: lt1; x: 26; y: 22; width: parent.width - 52; elide: Text.ElideRight; font.pixelSize: 21; w: 650
                text: win.cur ? ((win.cur.action === "install" ? "Installing " : (win.cur.action === "uninstall" ? "Removing " : "Updating ")) + (win.cur.n !== "" ? win.pretty(win.cur.n) : (win.cur.src === "pacman" ? "the system" : "everything"))) : "Nothing is running" }
            T { id: lt2; x: 26; y: lt1.y + lt1.height + 2; font.pixelSize: 14; color: Theme.i55; text: win.cur ? win.stage + (win.prog >= 0 ? "  " + Math.round(win.prog * 100) + "%" : "") + (win.queue.length > 0 ? "   and " + win.queue.length + " waiting" : "") : "" }
            Rectangle { x: 26; y: lt2.y + lt2.height + 12; width: parent.width - 52; height: parent.height - y - 84; radius: 18; color: Theme.cardbg; clip: true
                Flickable { SmoothWheel {}
id: lgf; anchors.fill: parent; anchors.margins: 12; contentHeight: lgt.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                    Text { id: lgt; width: lgf.width; wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 12; color: Theme.i62; text: win.logLines.length ? win.logLines.join("\n") : "No output yet" } } }
            Row { anchors.right: parent.right; anchors.rightMargin: 24; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; spacing: 10
                Item { visible: !!win.cur; width: stt.implicitWidth + 40; height: 42
                    Rectangle { anchors.fill: parent; radius: 21; color: Theme.errbg }
                    T { id: stt; anchors.centerIn: parent; text: "Stop"; font.pixelSize: 16; w: 650; color: Theme.errfg }
                    MouseArea { anchors.fill: parent; onClicked: { win.stopJob(win.cur.id); win.logOpen = false } } }
                Item { width: clt.implicitWidth + 40; height: 42
                    Rectangle { anchors.fill: parent; radius: 21; color: Theme.moonbg }
                    T { id: clt; anchors.centerIn: parent; text: "Close"; font.pixelSize: 16; w: 600; color: Theme.acc }
                    MouseArea { anchors.fill: parent; onClicked: win.logOpen = false } } }
        }
    }

    // ---- sure about the AUR? ----
    Item {
        visible: win.confirm !== null
        anchors.fill: parent
        MouseArea { anchors.fill: parent; onClicked: win.confirm = null }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: .4 }
        Rectangle {
            anchors.centerIn: parent
            width: 460; height: ccol.implicitHeight + 44; radius: 30; color: Theme.menubg; border.color: Theme.glassBorder
            MouseArea { anchors.fill: parent }
            Column { id: ccol; x: 26; y: 24; width: parent.width - 52; spacing: 12
                T { text: "Build " + (win.confirm ? win.pretty(win.confirm.n) : "") + " from the AUR?"; font.pixelSize: 22; w: 650; width: parent.width; wrapMode: Text.Wrap }
                T { text: "The AUR is a shelf of recipes written by users. Nobody checks them. Installing runs the recipe on this computer, builds the program and installs it. That can take a while and needs about 1 GB of free room."; font.pixelSize: 15; color: Theme.i62; width: parent.width; wrapMode: Text.Wrap }
                Row { spacing: 8
                    Spin { visible: win.aurArch === null; anchors.verticalCenter: parent.verticalCenter }
                    T { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 15; w: 600
                        color: win.aurArch && win.aurArch.ok && !win.aurArch.fits ? Theme.errfg : (win.aurArch && win.aurArch.ok ? Theme.acc : Theme.i55)
                        text: win.aurArch === null ? "Checking if it builds for ARM..." : (!win.aurArch.ok ? "Could not read the recipe" : (win.aurArch.fits ? "The recipe says it builds for this ARM computer" : "Builds only for " + win.aurArch.arch.join(", ") + ", not for ARM")) } }
                Row { spacing: 10; anchors.right: parent.right
                    Item { width: nt.implicitWidth + 40; height: 42
                        Rectangle { anchors.fill: parent; radius: 21; color: Theme.moonbg }
                        T { id: nt; anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 16; w: 600; color: Theme.acc }
                        MouseArea { anchors.fill: parent; onClicked: win.confirm = null } }
                    Item { width: yt.implicitWidth + 40; height: 42; opacity: win.aurArch && win.aurArch.ok && win.aurArch.fits ? 1 : .45
                        Rectangle { anchors.fill: parent; radius: 21; color: Theme.acc }
                        T { id: yt; anchors.centerIn: parent; text: "Build and install"; font.pixelSize: 16; w: 650; color: Theme.onacc }
                        MouseArea { anchors.fill: parent; enabled: !!win.aurArch && win.aurArch.ok && win.aurArch.fits; onClicked: { var e = win.confirm; win.confirm = null; win.enqueue("aur", "install", e.n) } } }
                }
            }
        }
    }
}
