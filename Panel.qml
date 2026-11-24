import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "CatFrames.js" as CatFrames

Panel {
  id: root
  moduleName: "mrnv.catrun"
  ipcTarget: "mrnv.catrun"
  manageIpc: false

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  // Persisted settings from shell.json layout entry.
  readonly property int catSize: Model.clampCatSize(setting("catSize", 16))
  property int catSizePreview: -1
  readonly property int effectiveCatSize: catSizePreview > 0 ? catSizePreview : catSize
  readonly property bool showPercent: setting("showPercent", false) === true
  readonly property int sleepThreshold: Model.clampSleepThreshold(setting("sleepThreshold", 0))
  readonly property bool invertDirection: setting("invertDirection", false) === true
  readonly property string raceMode: Model.clampRaceMode(setting("raceMode", "race"))

  // Live telemetry state (CPU, GPU, RAM, Disk, Net).
  property var prevStat: null
  property real cpuPercent: 0
  property real userPercent: 0
  property real systemPercent: 0
  property real iowaitPercent: 0
  property int cpuCores: 1
  property real load1: 0
  property real load5: 0
  property real load15: 0

  property real memTotalBytes: 0
  property real memUsedBytes: 0
  property real memAvailableBytes: 0
  property real memCachedBytes: 0
  property real memUsedPercent: 0

  property bool gpuAvailable: false
  property real gpuPercent: 0
  property string gpuName: ""
  property int gpuVramUsedMb: 0
  property int gpuVramTotalMb: 0
  property int gpuTempC: -1

  property var prevDisk: null
  property real prevDiskTs: 0
  property real diskPercent: 0
  property real diskReadBps: 0
  property real diskWriteBps: 0
  property real diskTotalBps: 0
  property int diskDeviceCount: 0

  property var prevNet: null
  property real prevNetTs: 0
  property real netPercent: 0
  property real netRxBps: 0
  property real netTxBps: 0
  property real netTotalBps: 0
  property string netActiveIface: ""

  property var topProcesses: []

  // Cat Gang race state (5 device cats: cpu, gpu, ram, disk, net).
  property var catGang: Model.createCatGang()
  property int raceTick: 0
  property real lastRaceStepTs: 0
  property string selectedDeviceId: "cpu"
  property bool settingsExpanded: false

  // Bar cat animation state.
  property bool paused: false
  property int frameIndex: 0
  readonly property bool sleeping: Model.isSleeping(cpuPercent, paused, sleepThreshold)
  readonly property int frameIntervalMs: Model.frameIntervalMs(cpuPercent, paused, sleepThreshold)
  readonly property real currentFps: Model.framesPerSecond(frameIntervalMs)
  readonly property bool catMirrored: invertDirection !== Commons.I18n.rightToLeft

  // Theme tokens.
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Localized strings bound reactively so language changes apply live.
  readonly property string titleText: Model.sanitizeText(strings.t("plugin.title", "CatRun"), 32)
  readonly property string paceText: Model.sanitizeText(strings.t(Model.paceKey(cpuPercent, paused, sleepThreshold)), 48)
  readonly property string cpuPercentText: Commons.I18n.formatNumber(Math.round(cpuPercent))
  readonly property string barTooltipText: Model.buildTooltip(titleText, cpuPercentText, paceText)
  readonly property string pauseHintText: Model.sanitizeText(
    paused ? strings.t("toggle.resumeHint") : strings.t("toggle.pauseHint"), 64)

  readonly property string leaderSummaryText: {
    var _ = raceTick
    var leader = Model.findLeader(catGang)
    if (!leader) return paceText
    var devName = Model.sanitizeText(strings.t(leader.deviceKey, leader.id.toUpperCase()), 24)
    var catName = Model.sanitizeText(strings.t(leader.catKey, ""), 24)
    return Model.sanitizeText(strings.t("race.leader", "Leader: %1 (%2)").arg(catName).arg(devName), 64)
  }

  readonly property string leaderCoat: {
    var _ = raceTick
    var leader = Model.findLeader(catGang)
    return leader ? leader.coat : foreground
  }
  readonly property string leaderAccent: {
    var _ = raceTick
    var leader = Model.findLeader(catGang)
    return leader ? leader.accent : foreground
  }
  readonly property string leaderVariant: {
    var _ = raceTick
    var leader = Model.findLeader(catGang)
    return leader ? leader.variant : ""
  }

  readonly property var selectedRacer: {
    var _ = raceTick
    for (var i = 0; i < catGang.length; i++) {
      if (catGang[i].id === selectedDeviceId) return catGang[i]
    }
    return catGang.length > 0 ? catGang[0] : null
  }

  readonly property var secondaryLaneLabels: {
    var _ = raceTick
    return {
      cpu: Commons.I18n.formatNumber(cpuCores) + "c",
      gpu: gpuTempC >= 0 ? (Commons.I18n.formatNumber(gpuTempC) + "°C") : (gpuAvailable ? "" : "—"),
      ram: memTotalBytes > 0 ? Model.formatGiB(memUsedBytes, Commons.I18n.formatNumber) : "",
      disk: diskTotalBps > 0 ? Model.formatByteRate(diskTotalBps, Commons.I18n.formatNumber) : strings.t("stat.idle", "Idle"),
      net: netTotalBps > 0 ? Model.formatByteRate(netTotalBps, Commons.I18n.formatNumber) : strings.t("stat.idle", "Idle")
    }
  }

  // Keyboard cursor model for the popup panel.
  readonly property var cursorRows: {
    var rows = [
      "hero",
      "lane:cpu",
      "lane:gpu",
      "lane:ram",
      "lane:disk",
      "lane:net",
      "settingsToggle"
    ]
    if (settingsExpanded) {
      rows.push("catSize", "showPercent", "invertDirection", "sleepThreshold")
    }
    rows.push("btop")
    return rows
  }
  property int cursorIndex: 0
  property bool cursorActive: false
  readonly property string currentRow: cursorActive ? cursorRows[Math.max(0, Math.min(cursorIndex, cursorRows.length - 1))] : ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onSleepingChanged: {
    frameIndex = 0
    scheduleNextBarFrame()
  }
  onPausedChanged: scheduleNextBarFrame()
  onSettingsExpandedChanged: clampCursor()

  function scheduleNextBarFrame() {
    if (root.paused || root.frameIntervalMs <= 0) {
      animTimer.stop()
      return
    }
    if (!animTimer.running) {
      animTimer.interval = Math.max(36, root.frameIntervalMs)
      animTimer.start()
    }
  }

  function clampCursor() {
    if (cursorIndex >= cursorRows.length) cursorIndex = Math.max(0, cursorRows.length - 1)
    if (cursorIndex < 0) cursorIndex = 0
  }

  function saveSettings(patch) {
    var next = Object.assign({}, root.settings || {}, patch)
    root.settings = next
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, next)
    }
  }

  function togglePercent() {
    saveSettings({ showPercent: !root.showPercent })
  }

  function toggleDirection() {
    saveSettings({ invertDirection: !root.invertDirection })
  }

  function setSleepThreshold(value) {
    saveSettings({ sleepThreshold: Model.clampSleepThreshold(value) })
  }

  function setCatSize(value) {
    var clamped = Model.clampCatSize(value)
    root.catSizePreview = -1
    saveSettings({ catSize: clamped })
  }

  function setRaceMode(mode) {
    var nextMode = Model.clampRaceMode(mode)
    saveSettings({ raceMode: nextMode })
    Model.rankCatGang(root.catGang, nextMode)
    root.raceTick++
  }

  function toggleRaceMode() {
    setRaceMode(root.raceMode === "race" ? "load" : "race")
  }

  function resetRace() {
    for (var i = 0; i < root.catGang.length; i++) {
      root.catGang[i].progress = 0
      root.catGang[i].laps = 0
      root.catGang[i].frameAccumMs = 0
      root.catGang[i].smoothUsage = root.catGang[i].usagePercent
    }
    Model.rankCatGang(root.catGang, root.raceMode)
    root.lastRaceStepTs = Date.now()
    root.raceTick++
  }

  function selectDevice(deviceId) {
    for (var i = 0; i < root.catGang.length; i++) {
      if (root.catGang[i].id === deviceId) {
        root.selectedDeviceId = deviceId
        return true
      }
    }
    return false
  }

  function syncGangUsage() {
    for (var i = 0; i < root.catGang.length; i++) {
      var r = root.catGang[i]
      if (r.id === "cpu") r.usagePercent = root.cpuPercent
      else if (r.id === "gpu") r.usagePercent = root.gpuPercent
      else if (r.id === "ram") r.usagePercent = root.memUsedPercent
      else if (r.id === "disk") r.usagePercent = root.diskPercent
      else if (r.id === "net") r.usagePercent = root.netPercent
    }
    Model.rankCatGang(root.catGang, root.raceMode)
    root.raceTick++
  }

  function stepRace() {
    var now = Date.now()
    var dt = root.lastRaceStepTs > 0 ? (now - root.lastRaceStepTs) : 50
    root.lastRaceStepTs = now
    Model.stepCatRace(root.catGang, dt, root.paused, root.sleepThreshold, root.raceMode)
    root.raceTick++
  }

  function togglePause() {
    root.paused = !root.paused
    if (!root.paused) root.lastRaceStepTs = Date.now()
  }

  function openActivityMonitor() {
    root.close()
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-launch-or-focus-tui btop")
    }
  }

  function consumeStat(raw) {
    var parsed = Model.parseProcStat(raw)
    if (!parsed) return
    if (root.prevStat) {
      var usage = Model.computeCpuUsage(root.prevStat, parsed)
      root.cpuPercent = usage.totalPercent
      root.userPercent = usage.userPercent
      root.systemPercent = usage.systemPercent
      root.iowaitPercent = usage.iowaitPercent
      root.cpuCores = usage.cores
    } else {
      root.cpuCores = parsed.cores
    }
    root.prevStat = parsed
    syncGangUsage()
  }

  function consumeDiskStats(raw) {
    var parsed = Model.parseDiskStats(raw)
    if (!parsed) return
    var now = Date.now()
    if (root.prevDisk && root.prevDiskTs > 0) {
      var usage = Model.computeDiskUsage(root.prevDisk, parsed, now - root.prevDiskTs)
      root.diskPercent = usage.usagePercent
      root.diskReadBps = usage.readBytesPerSec
      root.diskWriteBps = usage.writeBytesPerSec
      root.diskTotalBps = usage.totalBytesPerSec
      root.diskDeviceCount = usage.deviceCount
    } else {
      root.diskDeviceCount = parsed.deviceCount
    }
    root.prevDisk = parsed
    root.prevDiskTs = now
    syncGangUsage()
  }

  function consumeNetDev(raw) {
    var parsed = Model.parseNetDev(raw)
    if (!parsed) return
    var now = Date.now()
    if (root.prevNet && root.prevNetTs > 0) {
      var usage = Model.computeNetUsage(root.prevNet, parsed, now - root.prevNetTs)
      root.netPercent = usage.usagePercent
      root.netRxBps = usage.rxBytesPerSec
      root.netTxBps = usage.txBytesPerSec
      root.netTotalBps = usage.totalBytesPerSec
      root.netActiveIface = usage.activeIface
    }
    root.prevNet = parsed
    root.prevNetTs = now
    syncGangUsage()
  }

  function refreshFastProc() {
    statFile.reload()
    memFile.reload()
    diskFile.reload()
    netFile.reload()
  }

  function refreshDetails() {
    loadFile.reload()
    if (!gpuProc.running) gpuProc.running = true
    if (!psProc.running) psProc.running = true
  }

  function moveCursor(delta) {
    var next = root.cursorIndex + delta
    if (next < 0) next = 0
    if (next >= root.cursorRows.length) next = root.cursorRows.length - 1
    root.cursorIndex = next
  }

  function activateCursor() {
    var row = root.currentRow
    if (row === "hero") root.togglePause()
    else if (row.indexOf("lane:") === 0) root.selectDevice(row.slice(5))
    else if (row === "settingsToggle") root.settingsExpanded = !root.settingsExpanded
    else if (row === "showPercent") root.togglePercent()
    else if (row === "invertDirection") root.toggleDirection()
    else if (row === "btop") root.openActivityMonitor()
  }

  function setHoverRow(name) {
    var idx = root.cursorRows.indexOf(name)
    if (idx >= 0) {
      root.cursorActive = true
      root.cursorIndex = idx
    }
  }

  function stateJson() {
    var gangSnapshot = []
    for (var i = 0; i < root.catGang.length; i++) {
      var r = root.catGang[i]
      gangSnapshot.push({
        id: r.id,
        usagePercent: Math.round(r.usagePercent * 10) / 10,
        smoothUsage: Math.round(r.smoothUsage * 10) / 10,
        speedMultiplier: r.speedMultiplier,
        progress: Math.round(r.progress * 1000) / 1000,
        laps: r.laps,
        rank: r.rank,
        sleeping: r.sleeping
      })
    }
    return JSON.stringify({
      cpuPercent: Math.round(root.cpuPercent * 10) / 10,
      userPercent: Math.round(root.userPercent * 10) / 10,
      systemPercent: Math.round(root.systemPercent * 10) / 10,
      iowaitPercent: Math.round(root.iowaitPercent * 10) / 10,
      cores: root.cpuCores,
      gpuPercent: Math.round(root.gpuPercent * 10) / 10,
      gpuAvailable: root.gpuAvailable,
      diskPercent: Math.round(root.diskPercent * 10) / 10,
      netPercent: Math.round(root.netPercent * 10) / 10,
      pace: Model.paceKey(root.cpuPercent, root.paused, root.sleepThreshold),
      sleeping: root.sleeping,
      paused: root.paused,
      frameIndex: root.frameIndex,
      intervalMs: root.frameIntervalMs,
      fps: root.currentFps,
      catSize: root.catSize,
      showPercent: root.showPercent,
      sleepThreshold: root.sleepThreshold,
      invertDirection: root.invertDirection,
      raceMode: root.raceMode,
      selectedDeviceId: root.selectedDeviceId,
      memUsedPercent: Math.round(root.memUsedPercent * 10) / 10,
      gang: gangSnapshot
    })
  }

  ShellIpc {
    target: "mrnv.catrun"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function pause(): string { root.paused = true; return "paused" }
    function resume(): string { root.paused = false; root.lastRaceStepTs = Date.now(); return "running" }
    function togglePause(): string { root.togglePause(); return root.paused ? "paused" : "running" }
    function togglePercent(): string { root.togglePercent(); return root.showPercent ? "on" : "off" }
    function setSize(px: string): string { root.setCatSize(Number(px)); return String(root.catSize) }
    function setRaceMode(mode: string): string { root.setRaceMode(mode); return root.raceMode }
    function resetRace(): string { root.resetRace(); return "reset" }
    function selectDevice(id: string): string { return root.selectDevice(id) ? root.selectedDeviceId : "invalid" }
    function state(): string { return root.stateJson() }
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      lastRaceStepTs = Date.now()
      refreshFastProc()
      refreshDetails()
    } else {
      catSizePreview = -1
    }
  }

  Component.onCompleted: {
    statFile.reload()
    memFile.reload()
    scheduleNextBarFrame()
  }

  // Zero-subprocess /proc readers.
  FileView {
    id: statFile
    path: "/proc/stat"
    watchChanges: false
    printErrors: false
    onLoaded: root.consumeStat(text())
  }

  FileView {
    id: loadFile
    path: "/proc/loadavg"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var parsed = Model.parseLoadAvg(text())
      root.load1 = parsed.load1
      root.load5 = parsed.load5
      root.load15 = parsed.load15
    }
  }

  FileView {
    id: memFile
    path: "/proc/meminfo"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var parsed = Model.parseMemInfo(text())
      root.memTotalBytes = parsed.totalBytes
      root.memUsedBytes = parsed.usedBytes
      root.memAvailableBytes = parsed.availableBytes
      root.memCachedBytes = parsed.cachedBytes
      root.memUsedPercent = parsed.usedPercent
      root.syncGangUsage()
    }
  }

  FileView {
    id: diskFile
    path: "/proc/diskstats"
    watchChanges: false
    printErrors: false
    onLoaded: root.consumeDiskStats(text())
  }

  FileView {
    id: netFile
    path: "/proc/net/dev"
    watchChanges: false
    printErrors: false
    onLoaded: root.consumeNetDev(text())
  }

  // Fixed local GPU sensor probe (runs only while popup is open; avoids waking suspended dGPUs).
  Process {
    id: gpuProc
    command: [
      "sh", "-c",
      "for p in /sys/class/drm/card*/device/gpu_busy_percent; do "
      + "[ -r \"$p\" ] || continue; "
      + "card=\"${p#/sys/class/drm/}\"; card=\"${card%%/*}\"; "
      + "val=$(cat \"$p\" 2>/dev/null); "
      + "[ -n \"$val\" ] && printf 'DRM|%s|%s\\n' \"$card\" \"$val\"; "
      + "done; "
      + "if command -v nvidia-smi >/dev/null 2>&1; then "
      + "nv_active=0; found_nv=0; "
      + "for v in /sys/class/drm/card*/device/vendor; do "
      + "[ -r \"$v\" ] || continue; "
      + "if [ \"$(cat \"$v\" 2>/dev/null)\" = \"0x10de\" ]; then "
      + "found_nv=1; st=\"${v%/vendor}/power/runtime_status\"; "
      + "if [ ! -r \"$st\" ] || [ \"$(cat \"$st\" 2>/dev/null)\" = \"active\" ]; then nv_active=1; fi; "
      + "fi; done; "
      + "if [ \"$found_nv\" -eq 0 ] || [ \"$nv_active\" -eq 1 ]; then "
      + "nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null "
      + "| awk -F', *' '{printf \"NV|%s|%s|%s|%s|%s\\n\",$1,$2,$3,$4,$5}'; "
      + "fi; fi"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseGpuProbe(String(text || ""))
        root.gpuAvailable = parsed.available
        root.gpuPercent = parsed.usagePercent
        root.gpuName = parsed.name
        root.gpuVramUsedMb = parsed.vramUsedMb
        root.gpuVramTotalMb = parsed.vramTotalMb
        root.gpuTempC = parsed.tempC
        root.syncGangUsage()
      }
    }
  }

  // Top processes process only runs while the popup panel is open.
  Process {
    id: psProc
    command: ["ps", "-eo", "pid=,pcpu=,comm=", "--sort=-pcpu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.topProcesses = Model.parseTopProcesses(String(text || ""), 4)
      }
    }
  }

  // Bar CPU polling when closed (lightweight 1.5s). When opened, fastProcTimer drives 4 Hz updates.
  Timer {
    id: cpuTimer
    interval: 1500
    running: !root.opened
    repeat: true
    onTriggered: statFile.reload()
  }

  // Zero-subprocess realtime /proc polling (4 Hz) while the race popup is open.
  Timer {
    id: fastProcTimer
    interval: 250
    running: root.opened
    repeat: true
    onTriggered: root.refreshFastProc()
  }

  // Subprocess telemetry (GPU probe + top processes + loadavg) while popup is open.
  Timer {
    id: detailTimer
    interval: 900
    running: root.opened
    repeat: true
    onTriggered: root.refreshDetails()
  }

  // Self-rearming bar cat frame timer: setting `interval` only inside
  // onTriggered prevents rapid /proc updates (4 Hz while popup is open) from
  // resetting the timer before a slower frame completes.
  Timer {
    id: animTimer
    interval: 200
    running: false
    repeat: false
    onTriggered: {
      if (root.paused || root.frameIntervalMs <= 0) return
      var count = root.sleeping ? CatFrames.SLEEP_FRAMES.length : CatFrames.RUN_FRAMES.length
      root.frameIndex = (root.frameIndex + 1) % count
      interval = Math.max(36, root.frameIntervalMs)
      start()
    }
  }

  // Smooth ~30 fps Cat Gang realtime race physics + per-cat gallop timer (ONLY while popup is open).
  Timer {
    id: raceTimer
    interval: 33
    running: root.opened && !root.paused
    repeat: true
    onTriggered: root.stepRace()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.barTooltipText

    readonly property real renderedCatHeight: {
      var target = root.effectiveCatSize
      if (vertical) {
        var maxHeight = Math.max(8, (barSize - 4) / barCat.aspectRatio)
        return Math.min(target, maxHeight)
      }
      return Math.min(target, Math.max(8, barSize - 2))
    }

    fixedWidth: vertical ? -1 : Math.max(Style.bar.iconSlot, barContent.implicitWidth + Style.space(10))
    fixedHeight: vertical ? Math.max(Style.bar.iconSlot, barContent.implicitHeight + Style.space(8)) : -1

    Row {
      id: barContent
      x: (button.width - width) / 2
      y: (button.height - height) / 2
      spacing: Style.space(4)
      scale: button.pressScale

      PlainText {
        visible: root.showPercent && !button.vertical
        text: root.cpuPercentText + "%"
        color: root.barForeground
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }

      CatIcon {
        id: barCat
        iconSize: button.renderedCatHeight
        frameIndex: root.frameIndex
        sleeping: root.sleeping
        mirrored: root.catMirrored
        iconColor: root.barForeground
        opacity: root.paused ? 0.45 : 1.0
        anchors.verticalCenter: parent.verticalCenter

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.togglePercent()
      else if (buttonCode === Qt.MiddleButton) root.togglePause()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: panelColumn.implicitHeight
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) {
          root.moveCursor(dy)
        } else if (dx !== 0) {
          if (root.currentRow === "catSize") root.setCatSize(root.catSize + dx)
          else if (root.currentRow === "sleepThreshold") root.setSleepThreshold(root.sleepThreshold + dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(ch) {
        if (ch === " ") root.togglePause()
        else if (ch === "m" || ch === "M") root.toggleRaceMode()
        else if (ch === "0") root.resetRace()
        else if (ch === "p" || ch === "P") root.togglePercent()
        else if (ch === "r" || ch === "R") root.toggleDirection()
        else if (ch === "b" || ch === "B") root.openActivityMonitor()
        else if (ch === "1") root.selectDevice("cpu")
        else if (ch === "2") root.selectDevice("gpu")
        else if (ch === "3") root.selectDevice("ram")
        else if (ch === "4") root.selectDevice("disk")
        else if (ch === "5") root.selectDevice("net")
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          // ---------- Hero ----------
          Item {
            id: heroWrapper
            width: parent.width
            implicitHeight: hero.implicitHeight

            readonly property bool ringVisible: root.currentRow === "hero"
            function focusHero() { root.setHoverRow("hero") }

            PanelHero {
              id: hero
              width: parent.width
              title: root.titleText
              detail: root.cpuPercentText + "%"
              meta: root.paused ? root.paceText : root.leaderSummaryText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.paused ? 0.5 : 1.0

              iconComponent: Component {
                CatIcon {
                  iconSize: Style.font.display
                  frameIndex: root.frameIndex
                  sleeping: root.sleeping
                  mirrored: root.catMirrored
                  iconColor: root.leaderCoat
                  accentColor: root.leaderAccent
                  variant: root.leaderVariant
                  showCrown: !root.paused && !root.sleeping
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: runSwitch
                  checked: !root.paused
                  hasCursor: heroWrapper.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) heroWrapper.focusHero() }
                  onToggled: root.togglePause()

                  PanelToolTip {
                    visible: runSwitch.containsMouse
                    text: root.pauseHintText
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- Cat Gang Device Race Arena ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(raceHeader.implicitHeight, raceControls.implicitHeight)

              PanelSectionHeader {
                id: raceHeader
                text: strings.t("section.race", "Cat Gang Race")
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: raceControls
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  text: strings.t("race.modeRace", "Race")
                  selected: root.raceMode === "race"
                  bordered: true
                  fontSize: Style.font.caption
                  fontFamily: root.fontFamily
                  foreground: root.foreground
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.setRaceMode("race")
                }

                Button {
                  text: strings.t("race.modeLoad", "Load")
                  selected: root.raceMode === "load"
                  bordered: true
                  fontSize: Style.font.caption
                  fontFamily: root.fontFamily
                  foreground: root.foreground
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.setRaceMode("load")
                }

                Button {
                  visible: root.raceMode === "race"
                  text: "↺"
                  tooltipText: Model.sanitizeText(strings.t("race.resetHint", "Reset race laps and positions"), 64)
                  bordered: true
                  fontSize: Style.font.caption
                  fontFamily: root.fontFamily
                  foreground: root.foreground
                  horizontalPadding: Style.space(7)
                  verticalPadding: Style.space(3)
                  onClicked: root.resetRace()
                }
              }
            }

            CatRaceTrack {
              id: raceTrack
              width: parent.width
              racers: root.catGang
              raceTick: root.raceTick
              raceMode: root.raceMode
              selectedDeviceId: root.selectedDeviceId
              cursorRow: root.currentRow
              paused: root.paused
              foreground: root.foreground
              dim: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              stringsObj: strings
              secondaryLabels: root.secondaryLaneLabels
              onLaneSelected: function(devId) { root.selectDevice(devId) }
              onLaneHovered: function(devId) { root.setHoverRow("lane:" + devId) }
            }

            PlainText {
              width: parent.width
              text: strings.t("race.hint", "Click a lane to inspect its device")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- Selected Cat / Device Inspector ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(inspectorHeaderRow.implicitHeight, inspectorBadge.implicitHeight)

              Row {
                id: inspectorHeaderRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Rectangle {
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: width / 2
                  color: root.selectedRacer ? root.selectedRacer.coat : root.foreground
                  anchors.verticalCenter: parent.verticalCenter
                }

                PanelSectionHeader {
                  text: {
                    var r = root.selectedRacer
                    if (!r) return strings.t("section.inspector", "Device Inspector")
                    return strings.t(r.deviceKey, r.id.toUpperCase()) + " · " + strings.t(r.catKey, "")
                  }
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PlainText {
                id: inspectorBadge
                text: {
                  var _ = root.raceTick
                  var r = root.selectedRacer
                  if (!r) return ""
                  var pace = strings.t(Model.paceKey(r.usagePercent, root.paused, root.sleepThreshold))
                  if (root.raceMode === "race") {
                    return pace + " · " + strings.tn("race.laps", r.laps).arg(Commons.I18n.formatNumber(r.laps))
                  }
                  return pace
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // CPU Inspector
            Column {
              visible: root.selectedDeviceId === "cpu"
              width: parent.width
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.spacing.md

                Repeater {
                  model: [
                    { label: strings.t("stat.user"), value: root.userPercent },
                    { label: strings.t("stat.system"), value: root.systemPercent },
                    { label: strings.t("stat.iowait"), value: root.iowaitPercent }
                  ]

                  delegate: BorderSurface {
                    required property var modelData
                    width: (parent.width - Style.spacing.md * 2) / 3
                    implicitHeight: statCol.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: Style.normalFillFor(root.foreground, root.accent)
                    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                    Column {
                      id: statCol
                      anchors.centerIn: parent
                      width: parent.width - Style.space(8)
                      spacing: Style.space(2)

                      PlainText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: Commons.I18n.formatNumber(modelData.value, 1) + "%"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      PlainText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.label.toUpperCase()
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                      }
                    }
                  }
                }
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(loadLabel.implicitHeight, loadValue.implicitHeight)

                PlainText {
                  id: loadLabel
                  text: strings.t("stat.load") + " · " + strings.tn("stat.cores", root.cpuCores).arg(Commons.I18n.formatNumber(root.cpuCores))
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  id: loadValue
                  text: Commons.I18n.formatNumber(root.load1, 2) + " · "
                    + Commons.I18n.formatNumber(root.load5, 2) + " · "
                    + Commons.I18n.formatNumber(root.load15, 2)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              // Top processes under CPU inspector
              Column {
                width: parent.width
                spacing: Style.space(4)

                PlainText {
                  text: strings.t("section.processes")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                PlainText {
                  visible: root.topProcesses.length === 0
                  text: strings.t("processes.empty")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Repeater {
                  model: root.topProcesses

                  delegate: Item {
                    required property var modelData
                    width: parent.width
                    implicitHeight: Math.max(procName.implicitHeight, procCpu.implicitHeight) + Style.space(2)

                    PlainText {
                      id: procName
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      anchors.left: parent.left
                      anchors.right: procCpu.left
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    PlainText {
                      id: procCpu
                      text: Commons.I18n.formatNumber(modelData.cpu, 1) + "%"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }
            }

            // GPU Inspector
            Column {
              visible: root.selectedDeviceId === "gpu"
              width: parent.width
              spacing: Style.space(6)

              PlainText {
                visible: !root.gpuAvailable
                text: strings.t("stat.gpuUnavailable", "No active GPU sensor")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              PlainText {
                visible: root.gpuAvailable && root.gpuName !== ""
                width: parent.width
                text: root.gpuName
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }

              Item {
                visible: root.gpuAvailable && root.gpuVramTotalMb > 0
                width: parent.width
                implicitHeight: Math.max(vramLabel.implicitHeight, vramValue.implicitHeight)

                PlainText {
                  id: vramLabel
                  text: strings.t("stat.vram", "VRAM")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  id: vramValue
                  text: Commons.I18n.formatNumber(root.gpuVramUsedMb) + " / " + Commons.I18n.formatNumber(root.gpuVramTotalMb) + " MiB"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Item {
                visible: root.gpuAvailable && root.gpuTempC >= 0
                width: parent.width
                implicitHeight: Math.max(tempLabel.implicitHeight, tempValue.implicitHeight)

                PlainText {
                  id: tempLabel
                  text: strings.t("stat.temp", "Temp")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  id: tempValue
                  text: Commons.I18n.formatNumber(root.gpuTempC) + "°C"
                  color: root.gpuTempC >= 82 ? Commons.Color.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // RAM Inspector
            Column {
              visible: root.selectedDeviceId === "ram"
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: Math.max(ramUsedLabel.implicitHeight, ramUsedValue.implicitHeight)

                PlainText {
                  id: ramUsedLabel
                  text: strings.t("stat.memory", "Memory")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  id: ramUsedValue
                  text: Model.formatGiB(root.memUsedBytes, Commons.I18n.formatNumber) + " / "
                    + Model.formatGiB(root.memTotalBytes, Commons.I18n.formatNumber)
                    + " (" + Commons.I18n.formatNumber(Math.round(root.memUsedPercent)) + "%)"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(ramAvailLabel.implicitHeight, ramAvailValue.implicitHeight)

                PlainText {
                  id: ramAvailLabel
                  text: strings.t("stat.available", "Available")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  id: ramAvailValue
                  text: Model.formatGiB(root.memAvailableBytes, Commons.I18n.formatNumber)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(ramCacheLabel.implicitHeight, ramCacheValue.implicitHeight)

                PlainText {
                  id: ramCacheLabel
                  text: strings.t("stat.cached", "Cached")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  id: ramCacheValue
                  text: Model.formatGiB(root.memCachedBytes, Commons.I18n.formatNumber)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // Disk Inspector
            Column {
              visible: root.selectedDeviceId === "disk"
              width: parent.width
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.spacing.md

                Repeater {
                  model: [
                    { label: strings.t("stat.read", "Read"), value: Model.formatByteRate(root.diskReadBps, Commons.I18n.formatNumber) },
                    { label: strings.t("stat.write", "Write"), value: Model.formatByteRate(root.diskWriteBps, Commons.I18n.formatNumber) }
                  ]

                  delegate: BorderSurface {
                    required property var modelData
                    width: (parent.width - Style.spacing.md) / 2
                    implicitHeight: diskCol.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: Style.normalFillFor(root.foreground, root.accent)
                    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                    Column {
                      id: diskCol
                      anchors.centerIn: parent
                      width: parent.width - Style.space(8)
                      spacing: Style.space(2)

                      PlainText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.value
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      PlainText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.label.toUpperCase()
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                      }
                    }
                  }
                }
              }

              PlainText {
                visible: root.diskDeviceCount > 0
                text: strings.tn("stat.drives", root.diskDeviceCount).arg(Commons.I18n.formatNumber(root.diskDeviceCount))
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Network Inspector
            Column {
              visible: root.selectedDeviceId === "net"
              width: parent.width
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.spacing.md

                Repeater {
                  model: [
                    { label: strings.t("stat.download", "Down"), value: Model.formatByteRate(root.netRxBps, Commons.I18n.formatNumber) },
                    { label: strings.t("stat.upload", "Up"), value: Model.formatByteRate(root.netTxBps, Commons.I18n.formatNumber) }
                  ]

                  delegate: BorderSurface {
                    required property var modelData
                    width: (parent.width - Style.spacing.md) / 2
                    implicitHeight: netCol.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: Style.normalFillFor(root.foreground, root.accent)
                    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                    Column {
                      id: netCol
                      anchors.centerIn: parent
                      width: parent.width - Style.space(8)
                      spacing: Style.space(2)

                      PlainText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.value
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      PlainText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.label.toUpperCase()
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                      }
                    }
                  }
                }
              }

              Item {
                visible: root.netActiveIface !== ""
                width: parent.width
                implicitHeight: Math.max(ifaceLabel.implicitHeight, ifaceValue.implicitHeight)

                PlainText {
                  id: ifaceLabel
                  text: strings.t("stat.interface", "Interface")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  id: ifaceValue
                  text: root.netActiveIface
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- Collapsible Settings & Quick Actions ----------
          Column {
            width: parent.width
            spacing: Style.space(6)

            CursorSurface {
              width: parent.width
              height: Style.spacing.popupRowHeight + Style.space(2)
              hasCursor: root.currentRow === "settingsToggle"
              foreground: root.foreground

              PanelSectionHeader {
                text: strings.t("section.settings")
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                text: root.settingsExpanded ? "▾" : (Commons.I18n.rightToLeft ? "◂" : "▸")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.setHoverRow("settingsToggle")
                onClicked: root.settingsExpanded = !root.settingsExpanded
              }
            }

            Column {
              visible: root.settingsExpanded
              width: parent.width
              spacing: Style.space(6)

              // Cat size slider
              Column {
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(catSizeHeader.implicitHeight, catSizeValue.implicitHeight)

                  PlainText {
                    id: catSizeHeader
                    text: strings.t("setting.catSize")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PlainText {
                    id: catSizeValue
                    text: Commons.I18n.formatNumber(Math.round(catSizeSlider.dragging ? catSizeSlider.liveValue : root.catSize)) + "px"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                CursorSurface {
                  width: parent.width
                  height: catSizeSlider.implicitHeight + Style.spacing.controlGap
                  hasCursor: root.currentRow === "catSize"
                  foreground: root.foreground
                  outline: true

                  PanelSlider {
                    id: catSizeSlider
                    bar: root.bar
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(6)
                    minimum: 8
                    maximum: 24
                    step: 1
                    integer: true
                    value: root.catSize
                    onMoved: function(v) { root.catSizePreview = Model.clampCatSize(v) }
                    onReleased: function(v) { root.setCatSize(v) }
                  }

                  HoverHandler {
                    onHoveredChanged: if (hovered) root.setHoverRow("catSize")
                  }
                }
              }

              // Show CPU % in bar
              CursorSurface {
                width: parent.width
                height: Style.spacing.popupRowHeight + Style.space(4)
                hasCursor: root.currentRow === "showPercent"
                foreground: root.foreground

                PlainText {
                  text: strings.t("setting.showPercent")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: percentSwitch.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }

                ToggleSwitch {
                  id: percentSwitch
                  checked: root.showPercent
                  interactive: false
                  foreground: root.foreground
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.setHoverRow("showPercent")
                  onClicked: root.togglePercent()
                }
              }

              // Run direction
              CursorSurface {
                width: parent.width
                height: Style.spacing.popupRowHeight + Style.space(4)
                hasCursor: root.currentRow === "invertDirection"
                foreground: root.foreground

                PlainText {
                  text: strings.t("setting.invertDirection")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: dirSwitch.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }

                ToggleSwitch {
                  id: dirSwitch
                  checked: root.invertDirection
                  interactive: false
                  foreground: root.foreground
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.setHoverRow("invertDirection")
                  onClicked: root.toggleDirection()
                }
              }

              // Sleep threshold slider
              Column {
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(sleepHeader.implicitHeight, sleepValue.implicitHeight)

                  PlainText {
                    id: sleepHeader
                    text: strings.t("setting.sleepThreshold")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PlainText {
                    id: sleepValue
                    text: {
                      var v = Math.round(sleepSlider.dragging ? sleepSlider.liveValue : root.sleepThreshold)
                      return v <= 0 ? strings.t("setting.sleepOff") : Commons.I18n.formatNumber(v) + "%"
                    }
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                CursorSurface {
                  width: parent.width
                  height: sleepSlider.implicitHeight + Style.spacing.controlGap
                  hasCursor: root.currentRow === "sleepThreshold"
                  foreground: root.foreground
                  outline: true

                  PanelSlider {
                    id: sleepSlider
                    bar: root.bar
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(6)
                    minimum: 0
                    maximum: 30
                    step: 1
                    integer: true
                    value: root.sleepThreshold
                    onReleased: function(v) { root.setSleepThreshold(v) }
                  }

                  HoverHandler {
                    onHoveredChanged: if (hovered) root.setHoverRow("sleepThreshold")
                  }
                }
              }
            }

            // Open btop button
            CursorSurface {
              width: parent.width
              height: Style.spacing.popupRowHeight + Style.space(4)
              hasCursor: root.currentRow === "btop"
              foreground: root.foreground

              PlainText {
                text: strings.t("action.openBtop")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                text: "btop"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.setHoverRow("btop")
                onClicked: root.openActivityMonitor()
              }
            }
          }
        }
      }
    }
  }
}
