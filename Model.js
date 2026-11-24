.pragma library

var MAX_PROC_BYTES = 65536
var MAX_PROCESS_OUTPUT = 65536
var MAX_PROCESS_NAME_LEN = 40
var MAX_DEVICE_NAME_LEN = 48
var MAX_TOOLTIP_LEN = 120

// Neutralizes markup-shaped text before passing dynamic strings into any
// shared tooltip or Omarchy-owned component whose internal Text format is not
// controlled by this plugin.
function sanitizeText(value, maxLen) {
  var limit = (typeof maxLen === "number" && maxLen > 0) ? Math.floor(maxLen) : 80
  var s = String(value === undefined || value === null ? "" : value)
  // Strip control chars (including newlines/tabs) and neutralize HTML/XML delimiters.
  s = s.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
  s = s.replace(/[<>]/g, "")
  s = s.replace(/\s+/g, " ").trim()
  if (s.length > limit) s = s.slice(0, limit)
  return s
}

function clamp(value, minVal, maxVal) {
  var n = Number(value)
  if (!isFinite(n)) return minVal
  if (n < minVal) return minVal
  if (n > maxVal) return maxVal
  return n
}

function clampSleepThreshold(value) {
  return Math.round(clamp(value, 0, 30))
}

function clampCatSize(value) {
  return Math.round(clamp(value, 8, 24))
}

function clampRaceMode(value) {
  return value === "load" ? "load" : "race"
}

function parseProcStat(raw) {
  if (typeof raw !== "string" || raw.length === 0) return null
  var bounded = raw.length > MAX_PROC_BYTES ? raw.slice(0, MAX_PROC_BYTES) : raw
  var lines = bounded.split("\n")
  var aggregate = null
  var cores = 0

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    if (line.indexOf("cpu ") === 0) {
      var parts = line.split(/\s+/)
      if (parts.length < 5) continue
      var user = Number(parts[1]) || 0
      var nice = Number(parts[2]) || 0
      var system = Number(parts[3]) || 0
      var idle = Number(parts[4]) || 0
      var iowait = Number(parts[5]) || 0
      var irq = Number(parts[6]) || 0
      var softirq = Number(parts[7]) || 0
      var steal = Number(parts[8]) || 0

      if (!isFinite(user) || !isFinite(system) || !isFinite(idle)) continue
      var idleAll = idle + iowait
      var nonIdle = user + nice + system + irq + softirq + steal
      var total = idleAll + nonIdle
      aggregate = {
        total: total,
        active: nonIdle,
        user: user + nice,
        system: system + irq + softirq + steal,
        iowait: iowait,
        idle: idle
      }
    } else if (/^cpu[0-9]+\s/.test(line)) {
      cores++
    }
  }

  if (!aggregate) return null
  aggregate.cores = cores > 0 ? cores : 1
  return aggregate
}

function computeCpuUsage(prev, curr) {
  if (!prev || !curr) {
    return {
      totalPercent: 0,
      userPercent: 0,
      systemPercent: 0,
      iowaitPercent: 0,
      cores: curr && curr.cores ? curr.cores : 1
    }
  }

  var dTotal = curr.total - prev.total
  if (!isFinite(dTotal) || dTotal <= 0) {
    return {
      totalPercent: 0,
      userPercent: 0,
      systemPercent: 0,
      iowaitPercent: 0,
      cores: curr.cores || prev.cores || 1
    }
  }

  var dActive = Math.max(0, curr.active - prev.active)
  var dUser = Math.max(0, curr.user - prev.user)
  var dSystem = Math.max(0, curr.system - prev.system)
  var dIowait = Math.max(0, curr.iowait - prev.iowait)

  return {
    totalPercent: clamp((dActive / dTotal) * 100, 0, 100),
    userPercent: clamp((dUser / dTotal) * 100, 0, 100),
    systemPercent: clamp((dSystem / dTotal) * 100, 0, 100),
    iowaitPercent: clamp((dIowait / dTotal) * 100, 0, 100),
    cores: curr.cores || prev.cores || 1
  }
}

function parseLoadAvg(raw) {
  if (typeof raw !== "string" || raw.length === 0) return { load1: 0, load5: 0, load15: 0 }
  var bounded = raw.length > 512 ? raw.slice(0, 512) : raw
  var parts = bounded.trim().split(/\s+/)
  return {
    load1: clamp(parseFloat(parts[0]), 0, 9999),
    load5: clamp(parseFloat(parts[1]), 0, 9999),
    load15: clamp(parseFloat(parts[2]), 0, 9999)
  }
}

function parseMemInfo(raw) {
  if (typeof raw !== "string" || raw.length === 0) {
    return { totalBytes: 0, availableBytes: 0, usedBytes: 0, cachedBytes: 0, usedPercent: 0 }
  }
  var bounded = raw.length > MAX_PROC_BYTES ? raw.slice(0, MAX_PROC_BYTES) : raw
  var lines = bounded.split("\n")
  var totalKb = 0
  var availKb = -1
  var freeKb = 0
  var buffersKb = 0
  var cachedKb = 0

  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^([A-Za-z0-9_()]+):\s+(\d+)/)
    if (!m) continue
    var key = m[1]
    var val = Number(m[2]) || 0
    if (key === "MemTotal") totalKb = val
    else if (key === "MemAvailable") availKb = val
    else if (key === "MemFree") freeKb = val
    else if (key === "Buffers") buffersKb = val
    else if (key === "Cached") cachedKb = val
  }

  if (totalKb <= 0) {
    return { totalBytes: 0, availableBytes: 0, usedBytes: 0, cachedBytes: 0, usedPercent: 0 }
  }

  var effectiveAvailKb = availKb >= 0 ? availKb : (freeKb + buffersKb + cachedKb)
  var usedKb = Math.max(0, totalKb - effectiveAvailKb)
  var totalBytes = totalKb * 1024
  var availableBytes = Math.max(0, effectiveAvailKb * 1024)
  var usedBytes = usedKb * 1024
  var cachedBytes = Math.max(0, (buffersKb + cachedKb) * 1024)
  var usedPercent = clamp((usedKb / totalKb) * 100, 0, 100)

  return {
    totalBytes: totalBytes,
    availableBytes: availableBytes,
    usedBytes: usedBytes,
    cachedBytes: cachedBytes,
    usedPercent: usedPercent
  }
}

function isWholeDiskName(name) {
  if (typeof name !== "string" || !name) return false
  // Match whole physical block devices (nvme0n1, sda, vda, mmcblk0) and skip partitions/zram/dm.
  return /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+|hd[a-z]+|mmcblk[0-9]+)$/.test(name)
}

function parseDiskStats(raw) {
  if (typeof raw !== "string" || raw.length === 0) return null
  var bounded = raw.length > MAX_PROC_BYTES ? raw.slice(0, MAX_PROC_BYTES) : raw
  var lines = bounded.split("\n")
  var devices = {}
  var count = 0

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split(/\s+/)
    // /proc/diskstats fields:
    // 0:major 1:minor 2:name 3:reads 4:readsMerged 5:sectorsRead 6:msRead
    // 7:writes 8:writesMerged 9:sectorsWritten 10:msWrite 11:ioInProgress 12:msIo
    if (parts.length < 13) continue
    var name = sanitizeText(parts[2], 24)
    if (!isWholeDiskName(name)) continue
    var sectorsRead = Number(parts[5]) || 0
    var sectorsWritten = Number(parts[9]) || 0
    var ioMs = Number(parts[12]) || 0
    if (!isFinite(sectorsRead) || !isFinite(sectorsWritten) || !isFinite(ioMs)) continue
    devices[name] = {
      sectorsRead: sectorsRead,
      sectorsWritten: sectorsWritten,
      ioMs: ioMs
    }
    count++
  }

  if (count === 0) return null
  return { devices: devices, deviceCount: count }
}

function computeDiskUsage(prev, curr, elapsedMs) {
  var count = (curr && curr.deviceCount) ? curr.deviceCount : (prev && prev.deviceCount ? prev.deviceCount : 0)
  if (!prev || !curr || !isFinite(elapsedMs) || elapsedMs <= 0) {
    return {
      usagePercent: 0,
      readBytesPerSec: 0,
      writeBytesPerSec: 0,
      totalBytesPerSec: 0,
      deviceCount: count
    }
  }

  var secs = elapsedMs / 1000
  var totalReadBytes = 0
  var totalWriteBytes = 0
  var maxBusyPct = 0

  for (var name in curr.devices) {
    if (!Object.prototype.hasOwnProperty.call(curr.devices, name)) continue
    var c = curr.devices[name]
    var p = prev.devices[name]
    if (!p) continue
    var dReadSectors = Math.max(0, c.sectorsRead - p.sectorsRead)
    var dWriteSectors = Math.max(0, c.sectorsWritten - p.sectorsWritten)
    var dIoMs = Math.max(0, c.ioMs - p.ioMs)
    totalReadBytes += dReadSectors * 512
    totalWriteBytes += dWriteSectors * 512
    var busyPct = clamp((dIoMs / elapsedMs) * 100, 0, 100)
    if (busyPct > maxBusyPct) maxBusyPct = busyPct
  }

  var readBps = totalReadBytes / secs
  var writeBps = totalWriteBytes / secs
  var totalBps = readBps + writeBps

  // Blend I/O busy time with log throughput so fast NVMe bursts still show
  // lively movement even when queue busy ms is short.
  var throughputPct = totalBps > 0
    ? clamp((Math.log(1 + totalBps / 4096) / Math.log(1 + (512 * 1024 * 1024) / 4096)) * 100, 0, 100)
    : 0
  var combinedPct = clamp(Math.max(maxBusyPct, throughputPct * 0.85), 0, 100)

  return {
    usagePercent: combinedPct,
    readBytesPerSec: Math.max(0, readBps),
    writeBytesPerSec: Math.max(0, writeBps),
    totalBytesPerSec: Math.max(0, totalBps),
    deviceCount: count
  }
}

function parseNetDev(raw) {
  if (typeof raw !== "string" || raw.length === 0) return null
  var bounded = raw.length > MAX_PROC_BYTES ? raw.slice(0, MAX_PROC_BYTES) : raw
  var lines = bounded.split("\n")
  var ifaces = {}
  var count = 0

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var colonIdx = line.indexOf(":")
    if (colonIdx < 0) continue
    var iface = sanitizeText(line.slice(0, colonIdx), 24)
    if (!iface || iface === "lo") continue
    var stats = line.slice(colonIdx + 1).trim().split(/\s+/)
    if (stats.length < 9) continue
    var rxBytes = Number(stats[0]) || 0
    var txBytes = Number(stats[8]) || 0
    if (!isFinite(rxBytes) || !isFinite(txBytes)) continue
    ifaces[iface] = { rxBytes: rxBytes, txBytes: txBytes }
    count++
  }

  if (count === 0) return null
  return { ifaces: ifaces, ifaceCount: count }
}

function computeNetUsage(prev, curr, elapsedMs) {
  if (!prev || !curr || !isFinite(elapsedMs) || elapsedMs <= 0) {
    return {
      usagePercent: 0,
      rxBytesPerSec: 0,
      txBytesPerSec: 0,
      totalBytesPerSec: 0,
      activeIface: ""
    }
  }

  var secs = elapsedMs / 1000
  var totalRx = 0
  var totalTx = 0
  var bestIface = ""
  var bestBytes = -1

  for (var name in curr.ifaces) {
    if (!Object.prototype.hasOwnProperty.call(curr.ifaces, name)) continue
    var c = curr.ifaces[name]
    var p = prev.ifaces[name]
    if (!p) continue
    var dRx = Math.max(0, c.rxBytes - p.rxBytes)
    var dTx = Math.max(0, c.txBytes - p.txBytes)
    var sum = dRx + dTx
    totalRx += dRx
    totalTx += dTx
    if (sum > bestBytes) {
      bestBytes = sum
      bestIface = sanitizeText(name, 24)
    }
  }

  var rxBps = totalRx / secs
  var txBps = totalTx / secs
  var totalBps = rxBps + txBps

  // Responsive log curve: 0 B/s -> 0%, 100 KB/s -> ~34%, 1 MB/s -> ~56%,
  // 10 MB/s -> ~78%, 100 MB/s -> 100%.
  var pct = totalBps > 0
    ? clamp((Math.log(1 + totalBps / 1024) / Math.log(1 + (100 * 1024 * 1024) / 1024)) * 100, 0, 100)
    : 0

  return {
    usagePercent: pct,
    rxBytesPerSec: Math.max(0, rxBps),
    txBytesPerSec: Math.max(0, txBps),
    totalBytesPerSec: Math.max(0, totalBps),
    activeIface: bestIface
  }
}

// Parses output from our fixed local GPU probe command:
//   DRM|<cardName>|<busyPercent>
//   NV|<gpuName>|<utilPercent>|<vramUsedMb>|<vramTotalMb>|<tempC>
function parseGpuProbe(raw) {
  var result = {
    available: false,
    usagePercent: 0,
    name: "",
    vramUsedMb: 0,
    vramTotalMb: 0,
    tempC: -1,
    source: ""
  }
  if (typeof raw !== "string" || raw.length === 0) return result
  var bounded = raw.length > 4096 ? raw.slice(0, 4096) : raw
  var lines = bounded.split("\n")

  var nvEntry = null
  var drmEntry = null

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("|")
    if (parts[0] === "NV" && parts.length >= 6) {
      var nvUtil = clamp(parseFloat(parts[2]), 0, 100)
      var nvUsed = Math.max(0, Math.round(clamp(parseFloat(parts[3]), 0, 1048576)))
      var nvTotal = Math.max(0, Math.round(clamp(parseFloat(parts[4]), 0, 1048576)))
      var nvTemp = Math.round(clamp(parseFloat(parts[5]), -20, 150))
      var nvName = sanitizeText(parts[1], MAX_DEVICE_NAME_LEN)
      if (!nvEntry || nvUtil > nvEntry.usagePercent) {
        nvEntry = {
          available: true,
          usagePercent: nvUtil,
          name: nvName || "NVIDIA GPU",
          vramUsedMb: nvUsed,
          vramTotalMb: nvTotal,
          tempC: isFinite(parseFloat(parts[5])) ? nvTemp : -1,
          source: "nvidia"
        }
      }
    } else if (parts[0] === "DRM" && parts.length >= 3) {
      var drmUtil = clamp(parseFloat(parts[2]), 0, 100)
      var drmCard = sanitizeText(parts[1], 24)
      if (!drmEntry || drmUtil > drmEntry.usagePercent) {
        drmEntry = {
          available: true,
          usagePercent: drmUtil,
          name: drmCard ? ("GPU (" + drmCard + ")") : "Integrated GPU",
          vramUsedMb: 0,
          vramTotalMb: 0,
          tempC: -1,
          source: "drm"
        }
      }
    }
  }

  // Prefer whichever active GPU is doing more work right now; carry VRAM/temp
  // from NVIDIA if available and neither is busier, or show the busier one.
  if (nvEntry && drmEntry) {
    if (nvEntry.usagePercent >= drmEntry.usagePercent && nvEntry.usagePercent > 0) {
      return nvEntry
    }
    if (drmEntry.usagePercent > nvEntry.usagePercent) {
      return {
        available: true,
        usagePercent: drmEntry.usagePercent,
        name: drmEntry.name,
        vramUsedMb: nvEntry.vramUsedMb,
        vramTotalMb: nvEntry.vramTotalMb,
        tempC: nvEntry.tempC,
        source: "hybrid"
      }
    }
    return nvEntry
  }
  if (nvEntry) return nvEntry
  if (drmEntry) return drmEntry
  return result
}

function parseTopProcesses(raw, limit) {
  var maxItems = (typeof limit === "number" && limit > 0) ? Math.min(20, Math.floor(limit)) : 5
  if (typeof raw !== "string" || raw.length === 0) return []
  var bounded = raw.length > MAX_PROCESS_OUTPUT ? raw.slice(0, MAX_PROCESS_OUTPUT) : raw
  var lines = bounded.split("\n")
  var list = []

  for (var i = 0; i < lines.length && list.length < maxItems; i++) {
    var line = lines[i].trim()
    if (!line) continue
    // Expected format from `ps -eo pid=,pcpu=,comm= --sort=-pcpu`: "<pid> <pcpu> <comm...>"
    var m = line.match(/^(\d+)\s+([0-9]+(?:\.[0-9]+)?)\s+(.+)$/)
    if (!m) continue
    var pid = parseInt(m[1], 10)
    var cpu = clamp(parseFloat(m[2]), 0, 9999)
    var name = sanitizeText(m[3], MAX_PROCESS_NAME_LEN)
    if (!name) continue
    list.push({
      pid: isFinite(pid) ? pid : 0,
      cpu: cpu,
      name: name
    })
  }
  return list
}

function isSleeping(cpuPercent, paused, sleepThreshold) {
  if (paused) return false
  var threshold = clampSleepThreshold(sleepThreshold)
  if (threshold <= 0) return false
  return clamp(cpuPercent, 0, 100) < threshold
}

function frameIntervalMs(cpuPercent, paused, sleepThreshold) {
  if (paused) return 0
  if (isSleeping(cpuPercent, paused, sleepThreshold)) return 950
  var pct = clamp(cpuPercent, 0, 100)
  // Wide dynamic cadence: 360ms slow lazy stroll at 0% -> 38ms blazing zoomies at 100%.
  var t = Math.pow(pct / 100, 0.78)
  return Math.round(360 - t * (360 - 38))
}

function framesPerSecond(intervalMs) {
  if (!isFinite(intervalMs) || intervalMs <= 0) return 0
  return Math.round((1000 / intervalMs) * 10) / 10
}

function paceKey(cpuPercent, paused, sleepThreshold) {
  if (paused) return "pace.paused"
  if (isSleeping(cpuPercent, paused, sleepThreshold)) return "pace.sleeping"
  var pct = clamp(cpuPercent, 0, 100)
  if (pct < 20) return "pace.strolling"
  if (pct < 45) return "pace.trotting"
  if (pct < 70) return "pace.running"
  if (pct < 90) return "pace.sprinting"
  return "pace.zoomies"
}

// ---------- Cat Gang Device Race Engine ----------

var CAT_GANG_DEFS = [
  { id: "cpu",  deviceKey: "device.cpu",  catKey: "cat.cpu",  coat: "#f59e0b", accent: "#fef3c7", variant: "tabby" },
  { id: "gpu",  deviceKey: "device.gpu",  catKey: "cat.gpu",  coat: "#a78bfa", accent: "#ede9fe", variant: "visor" },
  { id: "ram",  deviceKey: "device.ram",  catKey: "cat.ram",  coat: "#34d399", accent: "#d1fae5", variant: "tuxedo" },
  { id: "disk", deviceKey: "device.disk", catKey: "cat.disk", coat: "#fb7185", accent: "#ffe4e6", variant: "calico" },
  { id: "net",  deviceKey: "device.net",  catKey: "cat.net",  coat: "#38bdf8", accent: "#e0f2fe", variant: "bolt" }
]

function createCatGang() {
  var gang = []
  for (var i = 0; i < CAT_GANG_DEFS.length; i++) {
    var d = CAT_GANG_DEFS[i]
    gang.push({
      id: d.id,
      deviceKey: d.deviceKey,
      catKey: d.catKey,
      coat: d.coat,
      accent: d.accent,
      variant: d.variant,
      usagePercent: 0,
      smoothUsage: 0,
      speedLapsPerSec: 0,
      speedMultiplier: 0,
      progress: 0,
      laps: 0,
      frameIndex: i % 5,
      frameAccumMs: 0,
      sleeping: false,
      rank: i + 1
    })
  }
  return gang
}

// Forward track velocity in laps per second as a steep, responsive function of
// realtime resource usage %: barely creeping at 0% -> blazing 0.65 laps/sec at 100%.
function raceSpeedLapsPerSec(usagePercent, paused, sleepThreshold) {
  if (paused) return 0
  if (isSleeping(usagePercent, paused, sleepThreshold)) return 0
  var pct = clamp(usagePercent, 0, 100)
  var t = pct / 100
  return 0.005 + 0.645 * Math.pow(t, 1.35)
}

function raceSpeedMultiplier(speedLapsPerSec) {
  var s = clamp(speedLapsPerSec, 0, 10)
  if (s <= 0) return 0
  // 0.10 laps/sec (~25% load) = 1.0x reference pace; 100% load = 6.5x zoomies.
  return Math.round((s / 0.10) * 10) / 10
}

// Advances all racers in-place by dtMs with fast-attack / smooth-release
// realtime velocity interpolation so resource spikes immediately accelerate cats
// and idle drops visibly slow them down.
function stepCatRace(racers, dtMs, paused, sleepThreshold, raceMode) {
  if (!racers || !racers.length) return racers
  var dt = clamp(dtMs, 0, 500)
  var dtSec = dt / 1000
  var mode = clampRaceMode(raceMode)

  for (var i = 0; i < racers.length; i++) {
    var r = racers[i]
    var targetPct = clamp(r.usagePercent, 0, 100)
    var prevSmooth = isFinite(Number(r.smoothUsage)) ? clamp(r.smoothUsage, 0, 100) : targetPct

    // Asymmetric exponential smoothing: punchy acceleration (120ms), smooth coast-down (280ms).
    var tau = targetPct >= prevSmooth ? 120 : 280
    var alpha = dt > 0 ? (1 - Math.exp(-dt / tau)) : 1
    var smoothPct = prevSmooth + (targetPct - prevSmooth) * alpha
    if (Math.abs(targetPct - smoothPct) < 0.05) smoothPct = targetPct
    r.smoothUsage = clamp(smoothPct, 0, 100)

    var asleep = isSleeping(targetPct, paused, sleepThreshold)
    r.sleeping = asleep

    var speed = raceSpeedLapsPerSec(r.smoothUsage, paused, sleepThreshold)
    r.speedLapsPerSec = speed
    r.speedMultiplier = raceSpeedMultiplier(speed)

    if (!paused) {
      var interval = frameIntervalMs(r.smoothUsage, false, sleepThreshold)
      if (interval > 0) {
        r.frameAccumMs = (Number(r.frameAccumMs) || 0) + dt
        if (r.frameAccumMs >= interval) {
          var steps = Math.min(3, Math.floor(r.frameAccumMs / interval))
          r.frameAccumMs = r.frameAccumMs % interval
          var frameCount = asleep ? 2 : 5
          r.frameIndex = ((Number(r.frameIndex) || 0) + steps) % frameCount
        }
      }

      if (mode === "race") {
        var nextProg = (Number(r.progress) || 0) + speed * dtSec
        if (nextProg >= 1.0) {
          var gained = Math.floor(nextProg)
          r.laps = Math.min(9999, (Number(r.laps) || 0) + gained)
          nextProg = nextProg - gained
        }
        r.progress = clamp(nextProg, 0, 0.9999)
      }
    }
  }

  return rankCatGang(racers, mode)
}

function rankCatGang(racers, raceMode) {
  if (!racers || !racers.length) return racers
  var mode = clampRaceMode(raceMode)
  var order = []
  for (var i = 0; i < racers.length; i++) {
    order.push({ idx: i, r: racers[i] })
  }
  order.sort(function(a, b) {
    if (mode === "race") {
      var scoreA = (Number(a.r.laps) || 0) + (Number(a.r.progress) || 0)
      var scoreB = (Number(b.r.laps) || 0) + (Number(b.r.progress) || 0)
      if (Math.abs(scoreB - scoreA) > 1e-6) return scoreB - scoreA
    }
    var uA = clamp(a.r.usagePercent, 0, 100)
    var uB = clamp(b.r.usagePercent, 0, 100)
    if (Math.abs(uB - uA) > 1e-6) return uB - uA
    return a.idx - b.idx
  })
  for (var k = 0; k < order.length; k++) {
    racers[order[k].idx].rank = k + 1
  }
  return racers
}

function findLeader(racers) {
  if (!racers || !racers.length) return null
  for (var i = 0; i < racers.length; i++) {
    if (racers[i].rank === 1) return racers[i]
  }
  return racers[0]
}

function formatGiB(bytes, formatNumberFn) {
  var gib = clamp(Number(bytes) / (1024 * 1024 * 1024), 0, 1048576)
  var formatted = typeof formatNumberFn === "function" ? formatNumberFn(gib, 1) : gib.toFixed(1)
  return formatted + " GiB"
}

function formatByteRate(bytesPerSec, formatNumberFn) {
  var bps = clamp(Number(bytesPerSec), 0, 1e12)
  var fmt = typeof formatNumberFn === "function"
    ? formatNumberFn
    : function(v, d) { return Number(v).toFixed(d) }
  if (bps < 1024) {
    return fmt(Math.round(bps), 0) + " B/s"
  }
  if (bps < 1024 * 1024) {
    return fmt(bps / 1024, bps < 10 * 1024 ? 1 : 0) + " KB/s"
  }
  if (bps < 1024 * 1024 * 1024) {
    return fmt(bps / (1024 * 1024), 1) + " MB/s"
  }
  return fmt(bps / (1024 * 1024 * 1024), 2) + " GB/s"
}

function buildTooltip(title, cpuFormatted, paceLabel) {
  var safeTitle = sanitizeText(title, 32)
  var safeCpu = sanitizeText(cpuFormatted, 16)
  var safePace = sanitizeText(paceLabel, 48)
  return sanitizeText(safeTitle + " · " + safeCpu + "% · " + safePace, MAX_TOOLTIP_LEN)
}
