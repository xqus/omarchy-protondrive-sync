import QtQuick
import QtQuick.Shapes
import qs.Commons

// A generic bidirectional-transfer glyph (not a Proton Drive brand mark --
// this is an unofficial, community plugin). Two solid arrows, one up-left
// (upload) and one down-right (download), built from straight path
// segments only so it renders identically regardless of the active icon
// font, following the same Shape/ShapePath approach as the first-party
// Dropbox bar-widget icon.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    Arrow { pointsUp: true; cx: root.width * 0.34; cy: root.height * 0.42 }
    Arrow { pointsUp: false; cx: root.width * 0.66; cy: root.height * 0.58 }
  }

  component Arrow: ShapePath {
    property real cx: 0
    property real cy: 0
    property bool pointsUp: true
    readonly property real armLen: root.height * 0.34
    readonly property real headW: root.width * 0.30
    readonly property real stemW: root.width * 0.11
    readonly property real sign: pointsUp ? -1 : 1

    fillColor: root.color
    strokeWidth: 0

    startX: cx - stemW / 2
    startY: cy - sign * armLen * 0.35
    PathLine { x: cx - stemW / 2; y: cy + sign * armLen * 0.65 }
    PathLine { x: cx - headW / 2; y: cy + sign * armLen * 0.65 }
    PathLine { x: cx; y: cy + sign * armLen }
    PathLine { x: cx + headW / 2; y: cy + sign * armLen * 0.65 }
    PathLine { x: cx + stemW / 2; y: cy + sign * armLen * 0.65 }
    PathLine { x: cx + stemW / 2; y: cy - sign * armLen * 0.35 }
  }
}
