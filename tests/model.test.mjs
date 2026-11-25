import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const dir = path.dirname(fileURLToPath(import.meta.url))
const pluginDir = path.resolve(dir, "..")

function loadQmlJs(filename) {
  const raw = fs.readFileSync(path.join(pluginDir, filename), "utf8")
  // Strip QML-only `.pragma library` directive before evaluating in Node VM.
  const code = raw.replace(/^\s*\.pragma\s+library\s*$/m, "")
  const sandbox = {}
  vm.createContext(sandbox)
  vm.runInContext(code, sandbox, { filename })
  return sandbox
}

const Model = loadQmlJs("Model.js")
const CatFrames = loadQmlJs("CatFrames.js")

// 1. /proc/stat parsing & CPU delta computation
{
  const s1 = Model.parseProcStat([
    "cpu  100 20 30 800 50 0 0 0 0 0",
    "cpu0 50 10 15 400 25 0 0 0 0 0",
    "cpu1 50 10 15 400 25 0 0 0 0 0"
  ].join("\n"))
  const s2 = Model.parseProcStat([
    "cpu  140 20 40 840 60 0 0 0 0 0",
    "cpu0 70 10 20 420 30 0 0 0 0 0",
    "cpu1 70 10 20 420 30 0 0 0 0 0"
  ].join("\n"))
  assert.equal(s1.cores, 2)
  const usage = Model.computeCpuUsage(s1, s2)
  assert.equal(usage.totalPercent, 50)
  assert.equal(usage.userPercent, 40)
  assert.equal(usage.systemPercent, 10)
  assert.equal(usage.iowaitPercent, 10)
  assert.equal(usage.cores, 2)
}

// 2. Zero / negative delta safety
{
  const s = Model.parseProcStat("cpu  100 0 0 100 0 0 0 0")
  const zero = Model.computeCpuUsage(s, s)
  assert.equal(zero.totalPercent, 0)
  assert.equal(Model.parseProcStat(""), null)
}

// 3. Load average & meminfo parsing
{
  const load = Model.parseLoadAvg("1.25 0.80 0.45 2/410 12345\n")
  assert.equal(load.load1, 1.25)
  assert.equal(load.load5, 0.8)
  assert.equal(load.load15, 0.45)

  const mem = Model.parseMemInfo([
    "MemTotal:       16777216 kB",
    "MemFree:         2097152 kB",
    "MemAvailable:    8388608 kB",
    "Buffers:          524288 kB",
    "Cached:          1572864 kB"
  ].join("\n"))
  assert.equal(mem.totalBytes, 16 * 1024 * 1024 * 1024)
  assert.equal(mem.usedPercent, 50)
  assert.equal(mem.cachedBytes, 2 * 1024 * 1024 * 1024)
  assert.equal(Model.formatGiB(mem.usedBytes), "8.0 GiB")
}

// 4. /proc/diskstats parsing & whole-disk delta computation
{
  const d1 = Model.parseDiskStats([
    " 259 0 nvme0n1 100 0 1000 10 200 0 2000 20 0 500 30",
    " 259 1 nvme0n1p1 100 0 1000 10 200 0 2000 20 0 500 30",
    " 252 0 zram0 10 0 100 0 10 0 100 0 0 0 0",
    "   8 0 sda 50 0 500 5 50 0 500 5 0 100 10"
  ].join("\n"))
  const d2 = Model.parseDiskStats([
    " 259 0 nvme0n1 150 0 3048 15 250 0 6096 25 0 1000 40",
    " 259 1 nvme0n1p1 150 0 3048 15 250 0 6096 25 0 1000 40",
    " 252 0 zram0 10 0 100 0 10 0 100 0 0 0 0",
    "   8 0 sda 50 0 500 5 50 0 500 5 0 100 10"
  ].join("\n"))
  // Partitions (nvme0n1p1) and zram0 must be excluded so we don't double-count.
  assert.equal(d1.deviceCount, 2)
  assert.equal(d1.devices.nvme0n1p1, undefined)
  assert.equal(d1.devices.zram0, undefined)

  const disk = Model.computeDiskUsage(d1, d2, 1000)
  // dIoMs = 500ms / 1000ms => 50% busy; read = 2048*512 = 1 MiB/s; write = 4096*512 = 2 MiB/s
  assert.equal(disk.readBytesPerSec, 1024 * 1024)
  assert.equal(disk.writeBytesPerSec, 2 * 1024 * 1024)
  assert.ok(disk.usagePercent >= 50 && disk.usagePercent <= 100, `Unexpected disk %: ${disk.usagePercent}`)
  assert.equal(Model.formatByteRate(1536 * 1024), "1.5 MB/s")
  assert.equal(Model.formatByteRate(512), "512 B/s")
}

// 5. /proc/net/dev parsing & throughput computation
{
  const n1 = Model.parseNetDev([
    "Inter-|   Receive |  Transmit",
    " face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed",
    "    lo: 999999 100 0 0 0 0 0 0 999999 100 0 0 0 0 0 0",
    "  wlo1: 1000000 1000 0 0 0 0 0 0 500000 500 0 0 0 0 0 0"
  ].join("\n"))
  const n2 = Model.parseNetDev([
    "Inter-|   Receive |  Transmit",
    " face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed",
    "    lo: 1999999 200 0 0 0 0 0 0 1999999 200 0 0 0 0 0 0",
    "  wlo1: 2048576 2000 0 0 0 0 0 0 1024288 1000 0 0 0 0 0 0"
  ].join("\n"))
  assert.equal(n1.ifaceCount, 1)
  assert.equal(n1.ifaces.lo, undefined)

  const net = Model.computeNetUsage(n1, n2, 1000)
  assert.equal(net.rxBytesPerSec, 1048576)
  assert.equal(net.txBytesPerSec, 524288)
  assert.equal(net.activeIface, "wlo1")
  assert.ok(net.usagePercent > 50 && net.usagePercent < 70, `Expected mid-range log net %, got ${net.usagePercent}`)
}

// 6. GPU probe parsing (DRM + NVIDIA hybrid & safety)
{
  const g1 = Model.parseGpuProbe([
    "DRM|card2|14",
    "NV|NVIDIA GeForce RTX 3060 Laptop GPU|68|1420|6144|62"
  ].join("\n"))
  assert.equal(g1.available, true)
  assert.equal(g1.usagePercent, 68)
  assert.equal(g1.vramUsedMb, 1420)
  assert.equal(g1.vramTotalMb, 6144)
  assert.equal(g1.tempC, 62)

  // Hybrid: iGPU busier than idle dGPU
  const g2 = Model.parseGpuProbe([
    "DRM|card2|22",
    "NV|NVIDIA GeForce RTX 3060|0|317|6144|48"
  ].join("\n"))
  assert.equal(g2.available, true)
  assert.equal(g2.usagePercent, 22)
  assert.equal(g2.tempC, 48)

  const gEmpty = Model.parseGpuProbe("")
  assert.equal(gEmpty.available, false)
}

// 7. Animation speed curve, pause, and sleep bands
{
  assert.equal(Model.frameIntervalMs(50, true, 5), 0)
  assert.equal(Model.paceKey(50, true, 5), "pace.paused")
  assert.equal(Model.isSleeping(3, false, 5), true)
  assert.equal(Model.frameIntervalMs(3, false, 5), 950)
  assert.equal(Model.paceKey(3, false, 5), "pace.sleeping")
  assert.equal(Model.isSleeping(3, false, 0), false)

  const slow = Model.frameIntervalMs(10, false, 5)
  const mid = Model.frameIntervalMs(50, false, 5)
  const fast = Model.frameIntervalMs(100, false, 5)
  assert.ok(slow > mid && mid > fast, `Expected monotonic speed up: ${slow} > ${mid} > ${fast}`)
  assert.equal(fast, 38)
  assert.equal(Model.paceKey(95, false, 5), "pace.zoomies")
  assert.equal(Model.clampCatSize(4), 8)
  assert.equal(Model.clampCatSize(16), 16)
  assert.equal(Model.clampCatSize(99), 24)
  assert.equal(Model.clampBarSpeed(undefined), 100)
  assert.equal(Model.clampBarSpeed("bad"), 100)
  assert.equal(Model.clampBarSpeed(10), 50)
  assert.equal(Model.clampBarSpeed(180), 180)
  assert.equal(Model.clampBarSpeed(999), 300)
  assert.equal(Model.formatSpeedMultiplier(100), "1.0x")
  assert.equal(Model.formatSpeedMultiplier(250), "2.5x")
  assert.equal(Model.clampRaceMode("load"), "load")
  assert.equal(Model.clampRaceMode("unknown"), "race")

  // Main bar cat runs noticeably faster than legacy curve at default 100% and scales with barSpeed
  assert.equal(Model.barFrameIntervalMs(50, true, 5, 100), 0)
  assert.equal(Model.barFrameIntervalMs(3, false, 5, 200), 950)
  const barSlow = Model.barFrameIntervalMs(10, false, 0, 50)
  const barDefault = Model.barFrameIntervalMs(10, false, 0, 100)
  const barFast = Model.barFrameIntervalMs(10, false, 0, 200)
  const barTurbo = Model.barFrameIntervalMs(10, false, 0, 300)
  assert.ok(barDefault < slow * 0.5, `Expected bar cat default to run >2x faster than legacy curve: bar=${barDefault}, legacy=${slow}`)
  assert.ok(barSlow > barDefault && barDefault > barFast && barFast > barTurbo,
    `Expected monotonic bar speed scaling: ${barSlow} > ${barDefault} > ${barFast} > ${barTurbo}`)
  assert.ok(Model.barFrameIntervalMs(100, false, 0, 300) >= 18, "Bar frame interval must respect safe minimum floor")
}

// 8. Cat Gang realtime race simulation, speed scaling, overtaking, lap counting, and ranking
{
  const gang = Model.createCatGang()
  assert.equal(gang.length, 5)
  gang[0].usagePercent = 15 // cpu
  gang[1].usagePercent = 90 // gpu (fastest!)
  gang[2].usagePercent = 45 // ram
  gang[3].usagePercent = 2  // disk (will sleep when threshold=5)
  gang[4].usagePercent = 30 // net

  // Verify steep realtime speed contrast between low and high load
  const vIdle = Model.raceSpeedLapsPerSec(0, false, 0)
  const vLow = Model.raceSpeedLapsPerSec(10, false, 0)
  const vHigh = Model.raceSpeedLapsPerSec(90, false, 0)
  assert.ok(vHigh > vLow * 10, `Expected strong speed contrast: high=${vHigh}, low=${vLow}`)
  assert.ok(vLow > vIdle, `Expected low usage faster than idle: low=${vLow}, idle=${vIdle}`)

  // Simulate 5 seconds in 33ms ticks (~150 ticks)
  for (let i = 0; i < 150; i++) {
    Model.stepCatRace(gang, 33, false, 5, "race")
  }
  const leader = Model.findLeader(gang)
  assert.equal(leader.id, "gpu", `Expected GPU cat to lead, got ${leader.id}`)
  assert.ok(gang[1].laps >= 2, `Expected GPU cat to finish multiple laps at 90%, got ${gang[1].laps}`)
  assert.ok(gang[1].speedMultiplier > gang[0].speedMultiplier * 5, "GPU speed multiplier should far exceed low CPU")
  assert.equal(gang[3].sleeping, true, "Expected Disk cat below threshold to sleep")
  assert.equal(gang[3].progress, 0, "Sleeping cat should stay put")
  assert.equal(gang[3].rank, 5, "Sleeping cat should be last")

  // Realtime deceleration: drop GPU to 0% and verify smooth slowdown
  const peakSpeed = gang[1].speedLapsPerSec
  gang[1].usagePercent = 0
  for (let i = 0; i < 40; i++) {
    Model.stepCatRace(gang, 33, false, 0, "race")
  }
  assert.ok(gang[1].speedLapsPerSec < peakSpeed * 0.1, "GPU cat should visibly decelerate when load drops")

  // Load mode ranks strictly by instantaneous usagePercent
  gang[0].usagePercent = 99
  Model.rankCatGang(gang, "load")
  assert.equal(Model.findLeader(gang).id, "cpu")
}

// 9. CatFrames safety, markings, crown, & wraparound
{
  assert.equal(CatFrames.RUN_FRAMES.length, 5)
  assert.equal(CatFrames.SLEEP_FRAMES.length, 2)
  assert.ok(CatFrames.pathFor(-1, false).startsWith("M "))
  assert.ok(CatFrames.pathFor(7, true).startsWith("M "))
  assert.ok(CatFrames.sleepZPath(3).startsWith("M "))
  assert.ok(CatFrames.CROWN_PATH.startsWith("M "))
  assert.ok(CatFrames.markingPath("tabby", false).startsWith("M "))
  assert.equal(CatFrames.markingPath("tabby", true), "")
  assert.equal(CatFrames.isFilledMarking("calico"), true)
  assert.equal(CatFrames.isFilledMarking("bolt"), false)
  assert.ok(CatFrames.speedStreakPath(5).startsWith("M "))
}

// 10. Plugin UI Safety regression tests: markup-shaped input across ALL dynamic sinks
{
  const tracker = '<img src="https://example.invalid/tracker">'
  const sanitized = Model.sanitizeText(tracker)
  assert.ok(!sanitized.includes("<") && !sanitized.includes(">"), "Must strip angle brackets")

  const psRaw = [
    `101 42.5 ${tracker}`,
    `102 15.0 <b>evil\nnewline</b>`,
    `103 8.1 ${"a".repeat(200)}`,
    `104 4.0 normal-proc`,
    `105 2.0 proc5`,
    `106 1.0 proc6-should-be-dropped`
  ].join("\n")

  const procs = Model.parseTopProcesses(psRaw, 5)
  assert.equal(procs.length, 5)
  for (const p of procs) {
    assert.ok(!p.name.includes("<") && !p.name.includes(">"), `Unsafe proc name: ${p.name}`)
    assert.ok(!/[\r\n\t]/.test(p.name), `Control char in proc name: ${p.name}`)
    assert.ok(p.name.length <= 40, `Unbounded proc name length: ${p.name.length}`)
  }

  // GPU & Network interface names with markup payloads
  const evilGpu = Model.parseGpuProbe(`NV|${tracker} <b>RTX</b>|55|512|4096|60`)
  assert.ok(!evilGpu.name.includes("<") && !evilGpu.name.includes(">"), `Unsafe GPU name: ${evilGpu.name}`)
  assert.ok(evilGpu.name.length <= 48)

  const evilNet1 = Model.parseNetDev(`  <b>eth0</b>: 100 0 0 0 0 0 0 0 100 0 0 0 0 0 0 0\n`)
  const evilNet2 = Model.parseNetDev(`  <b>eth0</b>: 2100 0 0 0 0 0 0 0 2100 0 0 0 0 0 0 0\n`)
  const evilNet = Model.computeNetUsage(evilNet1, evilNet2, 1000)
  assert.ok(!evilNet.activeIface.includes("<") && !evilNet.activeIface.includes(">"), `Unsafe iface: ${evilNet.activeIface}`)

  const tooltip = Model.buildTooltip("CatRun", "25", `${tracker} Zoomies`, `<b>1.5x</b>`)
  assert.ok(!tooltip.includes("<") && !tooltip.includes(">"), `Unsafe tooltip: ${tooltip}`)
  assert.ok(tooltip.includes("1.5x"), `Expected speed in tooltip: ${tooltip}`)
  assert.ok(tooltip.length <= 120)
}

// 11. Static check: ensure QML files never use raw AutoText `Text {` directly
//     and never bind animTimer's interval reactively to frameIntervalMs
{
  for (const qmlFile of ["Panel.qml", "CatIcon.qml", "CatRaceTrack.qml"]) {
    const src = fs.readFileSync(path.join(pluginDir, qmlFile), "utf8")
    assert.ok(!/\bText\s*\{/.test(src), `${qmlFile} should use PlainText instead of bare Text {}`)
  }
  const panelSrc = fs.readFileSync(path.join(pluginDir, "Panel.qml"), "utf8")
  assert.ok(!/interval:\s*Math\.max\([^)]*frameIntervalMs/.test(panelSrc),
    "animTimer must not reactively bind interval to frameIntervalMs (resets timer on fast /proc updates)")
}

// 12. Locale catalog check: both en.json and th.json are valid JSON with matching keys
{
  const en = JSON.parse(fs.readFileSync(path.join(pluginDir, "i18n/en.json"), "utf8"))
  const th = JSON.parse(fs.readFileSync(path.join(pluginDir, "i18n/th.json"), "utf8"))
  for (const key of Object.keys(en)) {
    assert.ok(Object.prototype.hasOwnProperty.call(th, key), `Missing Thai translation key: ${key}`)
  }
}

console.log("All CatRun Cat Gang model & UI safety tests passed!")
