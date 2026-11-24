import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Five-lane Cat Gang Grand Prix arena where each cat guards a hardware device
// (CPU, GPU, RAM, Disk, Net) and races at a speed scaled by its live usage.
BorderSurface {
  id: track

  property var racers: []
  property int raceTick: 0
  property string raceMode: "race"
  property string selectedDeviceId: "cpu"
  property string cursorRow: ""
  property bool paused: false
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.45)
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property var stringsObj: null
  property var secondaryLabels: ({})

  signal laneSelected(string deviceId)
  signal laneHovered(string deviceId)

  radius: Style.cornerRadius
  color: Style.normalFillFor(track.foreground, track.accent)
  borderSpec: Border.controlSpec("normal", track.foreground, track.accent)
  implicitHeight: lanesColumn.implicitHeight + Style.space(12)

  function tr(key, fallback) {
    if (track.stringsObj && typeof track.stringsObj.t === "function") {
      return Model.sanitizeText(track.stringsObj.t(key, fallback || key), 48)
    }
    return Model.sanitizeText(fallback || key, 48)
  }

  Column {
    id: lanesColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(6)
    spacing: Style.space(4)

    Repeater {
      id: laneRepeater
      model: track.racers.length

      delegate: CursorSurface {
        id: laneRow
        required property int index

        readonly property var racer: (track.racers && index < track.racers.length) ? track.racers[index] : null
        readonly property string deviceId: racer ? racer.id : ""
        readonly property bool isSelected: deviceId === track.selectedDeviceId
        readonly property color coatColor: racer ? racer.coat : track.foreground
        readonly property color markingColor: racer ? racer.accent : track.foreground
        // Read track.raceTick inside every primitive binding because stepCatRace
        // updates racer objects in place; binding an object property would suppress
        // QML change notifications when the reference stays identical.
        readonly property real usagePct: {
          var _ = track.raceTick
          return racer ? Model.clamp(racer.usagePercent, 0, 100) : 0
        }
        readonly property real smoothPct: {
          var _ = track.raceTick
          return racer ? Model.clamp(racer.smoothUsage, 0, 100) : 0
        }
        readonly property real speedMult: {
          var _ = track.raceTick
          return racer ? Model.clamp(racer.speedMultiplier, 0, 10) : 0
        }
        readonly property int catFrameIndex: {
          var _ = track.raceTick
          return racer ? (Number(racer.frameIndex) || 0) : 0
        }
        readonly property bool catSleeping: {
          var _ = track.raceTick
          return racer ? (racer.sleeping === true) : false
        }
        readonly property real posFraction: {
          var _ = track.raceTick
          if (!racer) return 0
          return track.raceMode === "load"
            ? Model.clamp(racer.smoothUsage / 100, 0, 1)
            : Model.clamp(racer.progress, 0, 1)
        }
        readonly property int lapsCount: {
          var _ = track.raceTick
          return racer ? (Number(racer.laps) || 0) : 0
        }
        readonly property int rankNum: {
          var _ = track.raceTick
          return racer ? (Number(racer.rank) || (index + 1)) : (index + 1)
        }
        readonly property bool isLeader: rankNum === 1
        readonly property string extraMetric: {
          var _ = track.raceTick
          return (track.secondaryLabels && track.secondaryLabels[deviceId]) ? String(track.secondaryLabels[deviceId]) : ""
        }

        width: lanesColumn.width
        height: Style.space(40)
        hasCursor: track.cursorRow === ("lane:" + deviceId)
        current: isSelected
        foreground: track.foreground

        Row {
          id: laneContent
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(8)

          // Left: Rank badge + Device / Cat name
          Item {
            id: labelCol
            width: Style.space(90)
            height: parent.height

            // Rank pill (#1 gets warm gold highlight)
            Rectangle {
              id: rankBadge
              width: Style.space(20)
              height: Style.space(18)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(4)) : 0
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: laneRow.isLeader
                ? Qt.rgba(0.98, 0.80, 0.08, 0.22)
                : Qt.rgba(track.foreground.r, track.foreground.g, track.foreground.b, 0.08)
              border.width: laneRow.isLeader ? 1 : 0
              border.color: laneRow.isLeader ? Qt.rgba(0.98, 0.80, 0.08, 0.7) : "transparent"

              PlainText {
                anchors.centerIn: parent
                text: "#" + Commons.I18n.formatNumber(laneRow.rankNum)
                color: laneRow.isLeader ? "#facc15" : track.dim
                font.family: track.fontFamily
                font.pixelSize: Math.max(9, Style.font.caption - 1)
                font.bold: true
              }
            }

            Column {
              anchors.left: rankBadge.right
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Row {
                spacing: Style.space(4)
                width: parent.width

                Rectangle {
                  width: Style.space(6)
                  height: Style.space(6)
                  radius: width / 2
                  color: laneRow.coatColor
                  anchors.verticalCenter: parent.verticalCenter
                }

                PlainText {
                  text: laneRow.racer ? track.tr(laneRow.racer.deviceKey, laneRow.deviceId.toUpperCase()) : ""
                  color: track.foreground
                  font.family: track.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                  width: Math.max(0, parent.width - Style.space(10))
                }
              }

              PlainText {
                text: laneRow.racer ? track.tr(laneRow.racer.catKey, "") : ""
                color: track.dim
                font.family: track.fontFamily
                font.pixelSize: Math.max(9, Style.font.caption - 1)
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // Center: The actual Race Lane with track markers, trail, finish line, and running cat!
          Item {
            id: runway
            width: Math.max(Style.space(80), laneContent.width - labelCol.width - statsCol.width - laneContent.spacing * 2)
            height: Style.space(28)
            anchors.verticalCenter: parent.verticalCenter
            clip: true

            readonly property bool rtl: LayoutMirroring.enabled || Commons.I18n.rightToLeft
            readonly property real finishWidth: Style.space(6)
            readonly property real usableWidth: Math.max(1, width - finishWidth - Style.space(2))
            readonly property real maxCatTravel: Math.max(0, usableWidth - runnerCat.width)
            readonly property real catXTarget: rtl
              ? (finishWidth + Style.space(2) + maxCatTravel * (1 - laneRow.posFraction))
              : (maxCatTravel * laneRow.posFraction)

            // Subtle track surface
            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(4)) : 0
              color: Qt.rgba(track.foreground.r, track.foreground.g, track.foreground.b, 0.045)
              border.width: 1
              border.color: laneRow.isSelected
                ? Qt.rgba(laneRow.coatColor.r, laneRow.coatColor.g, laneRow.coatColor.b, 0.45)
                : Qt.rgba(track.foreground.r, track.foreground.g, track.foreground.b, 0.10)
            }

            // Center dashed lane guide line
            Row {
              anchors.verticalCenter: parent.verticalCenter
              x: runway.rtl ? (runway.finishWidth + Style.space(4)) : Style.space(4)
              width: Math.max(0, runway.usableWidth - Style.space(8))
              spacing: Style.space(6)
              Repeater {
                model: Math.max(0, Math.floor((runway.usableWidth - Style.space(8)) / Style.space(12)))
                Rectangle {
                  width: Style.space(6)
                  height: 1
                  color: Qt.rgba(track.foreground.r, track.foreground.g, track.foreground.b, 0.14)
                }
              }
            }

            // 25% / 50% / 75% distance markers
            Repeater {
              model: [0.25, 0.5, 0.75]
              Rectangle {
                required property real modelData
                width: 1
                height: runway.height - Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                x: runway.rtl
                  ? (runway.finishWidth + Style.space(2) + runway.usableWidth * (1 - modelData))
                  : (runway.usableWidth * modelData)
                color: Qt.rgba(track.foreground.r, track.foreground.g, track.foreground.b, 0.10)
              }
            }

            // Colored speed/progress trail behind the cat (intensity scales with live speed)
            Rectangle {
              id: trail
              height: parent.height - 2
              y: 1
              x: runway.rtl ? (runnerCat.x + runnerCat.width * 0.4) : 1
              width: runway.rtl
                ? Math.max(0, (runway.width - 1) - x)
                : Math.max(0, Math.min(runway.usableWidth, runnerCat.x + runnerCat.width * 0.6) - 1)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(3)) : 0
              readonly property real speedGlow: 0.08 + (laneRow.smoothPct / 100) * 0.24 + (laneRow.isSelected ? 0.06 : 0)
              color: Qt.rgba(laneRow.coatColor.r, laneRow.coatColor.g, laneRow.coatColor.b, Math.min(0.42, speedGlow))
            }

            // Checkered finish line at the end of the lane
            Grid {
              id: finishLine
              columns: 2
              rows: 6
              x: runway.rtl ? 1 : (runway.width - runway.finishWidth - 1)
              y: 1
              width: runway.finishWidth
              height: runway.height - 2

              Repeater {
                model: 12
                Rectangle {
                  required property int index
                  width: finishLine.width / 2
                  height: finishLine.height / 6
                  readonly property bool darkSquare: ((Math.floor(index / 2) + (index % 2)) % 2) === 0
                  color: darkSquare
                    ? Qt.rgba(track.foreground.r, track.foreground.g, track.foreground.b, 0.42)
                    : Qt.rgba(track.foreground.r, track.foreground.g, track.foreground.b, 0.08)
                }
              }
            }

            // The Cat Gang Runner!
            CatIcon {
              id: runnerCat
              iconSize: Style.space(18)
              x: runway.catXTarget
              y: Math.round((runway.height - height) / 2)
              frameIndex: laneRow.catFrameIndex
              sleeping: laneRow.catSleeping
              mirrored: runway.rtl
              iconColor: laneRow.coatColor
              accentColor: laneRow.markingColor
              variant: laneRow.racer ? laneRow.racer.variant : ""
              showCrown: laneRow.isLeader && !laneRow.catSleeping
              speedLines: !track.paused && laneRow.smoothPct >= 35
              opacity: track.paused ? 0.5 : 1.0

              Behavior on x {
                enabled: track.raceMode === "load"
                NumberAnimation {
                  duration: Style.duration(180)
                  easing.type: Easing.Bezier
                  easing.bezierCurve: Style.easeOut
                }
              }

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.duration(160)
                  easing.type: Easing.OutCubic
                }
              }
            }
          }

          // Right: Live percentage & realtime speed / laps
          Column {
            id: statsCol
            width: Style.space(74)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            PlainText {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              text: Commons.I18n.formatNumber(Math.round(laneRow.usagePct)) + "%"
              color: laneRow.usagePct >= 85 ? Commons.Color.urgent : track.foreground
              font.family: track.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
            }

            PlainText {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              text: track.raceMode === "race"
                ? (Commons.I18n.formatNumber(laneRow.speedMult, 1) + "x · ★" + Commons.I18n.formatNumber(laneRow.lapsCount))
                : (laneRow.extraMetric !== "" ? laneRow.extraMetric : track.tr(Model.paceKey(laneRow.usagePct, track.paused, 0), ""))
              color: (track.raceMode === "race" && laneRow.smoothPct >= 35) ? laneRow.coatColor : track.dim
              font.family: track.fontFamily
              font.pixelSize: Math.max(9, Style.font.caption - 1)
              font.bold: track.raceMode === "race" && (laneRow.lapsCount > 0 || laneRow.smoothPct >= 35)
              elide: Text.ElideRight
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: track.laneHovered(laneRow.deviceId)
          onClicked: track.laneSelected(laneRow.deviceId)
        }
      }
    }
  }
}
