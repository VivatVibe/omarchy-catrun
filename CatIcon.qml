import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import "CatFrames.js" as CatFrames

// Fixed-box vector running cat icon. Using a transparent Rectangle root keeps
// IconContentBounds stable across animation frames so the bar icon never bobs
// in scale while legs extend and tuck.
Rectangle {
  id: root

  property real iconSize: Style.font.icon
  readonly property real aspectRatio: CatFrames.VIEWBOX_WIDTH / CatFrames.VIEWBOX_HEIGHT
  property int frameIndex: 0
  property bool sleeping: false
  property bool mirrored: false
  property color iconColor: Commons.Color.foreground
  property string variant: ""
  property color accentColor: Qt.lighter(iconColor, 1.45)
  property bool showCrown: false
  property color crownColor: "#facc15"
  property bool speedLines: false

  color: "transparent"
  width: iconSize * aspectRatio
  height: iconSize
  implicitWidth: iconSize * aspectRatio
  implicitHeight: iconSize

  readonly property real sx: width / CatFrames.VIEWBOX_WIDTH
  readonly property real sy: height / CatFrames.VIEWBOX_HEIGHT
  readonly property string activeMarking: CatFrames.markingPath(root.variant, root.sleeping)
  readonly property bool markingFilled: CatFrames.isFilledMarking(root.variant)

  Shape {
    id: shape
    width: CatFrames.VIEWBOX_WIDTH
    height: CatFrames.VIEWBOX_HEIGHT
    preferredRendererType: Shape.CurveRenderer
    antialiasing: true
    transform: [
      Scale {
        origin.x: CatFrames.VIEWBOX_WIDTH / 2
        origin.y: CatFrames.VIEWBOX_HEIGHT / 2
        xScale: root.mirrored ? -1 : 1
        yScale: 1
      },
      Scale {
        xScale: root.sx
        yScale: root.sy
      }
    ]

    // Speed lines trailing behind a sprinting cat
    ShapePath {
      fillColor: "transparent"
      strokeColor: (root.speedLines && !root.sleeping) ? Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 0.72) : "transparent"
      strokeWidth: (root.speedLines && !root.sleeping) ? 1.15 : 0
      capStyle: ShapePath.RoundCap
      PathSvg {
        path: (root.speedLines && !root.sleeping) ? CatFrames.speedStreakPath(root.frameIndex) : ""
      }
    }

    // Main cat silhouette
    ShapePath {
      fillColor: root.iconColor
      strokeWidth: 0
      PathSvg {
        path: CatFrames.pathFor(root.frameIndex, root.sleeping)
      }
    }

    // Gang member coat marking or accessory (stripes / visor / collar / calico / bolt)
    ShapePath {
      fillColor: (root.activeMarking !== "" && root.markingFilled) ? root.accentColor : "transparent"
      strokeColor: (root.activeMarking !== "" && !root.markingFilled) ? root.accentColor : "transparent"
      strokeWidth: (root.activeMarking !== "" && !root.markingFilled) ? (root.variant === "visor" ? 1.5 : 1.15) : 0
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: root.activeMarking
      }
    }

    // Leader #1 tiny crown
    ShapePath {
      fillColor: root.showCrown ? root.crownColor : "transparent"
      strokeWidth: 0
      PathSvg {
        path: root.showCrown ? CatFrames.CROWN_PATH : ""
      }
    }

    // Sleeping Zzz glyph
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.sleeping ? root.iconColor : "transparent"
      strokeWidth: root.sleeping ? 1.3 : 0
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: root.sleeping ? CatFrames.sleepZPath(root.frameIndex) : ""
      }
    }
  }
}
