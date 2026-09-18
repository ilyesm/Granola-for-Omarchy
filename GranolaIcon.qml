import QtQuick
import qs.Commons
import qs.Ui

// Rectangles only. Qt Shape/SVG paths vanish in tiny bar slots.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool recording: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real stroke: Math.max(1.8, iconSize * 0.12)
  readonly property real hubSize: Math.max(2.8, iconSize * 0.18)

  Item {
    id: mark
    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      anchors.margins: root.iconSize * 0.04
      radius: width / 2
      color: "transparent"
      border.color: root.color
      border.width: root.stroke
    }

    Rectangle {
      width: parent.width * 0.58
      height: width
      radius: width / 2
      color: "transparent"
      border.color: root.color
      border.width: root.stroke
      x: parent.width * 0.28
      y: parent.height * 0.22
    }

    Rectangle {
      width: root.hubSize
      height: root.hubSize
      radius: width / 2
      color: root.color
      x: parent.width * 0.42 - width / 2
      y: parent.height * 0.58 - height / 2
    }
  }

  SequentialAnimation {
    running: root.recording
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { target: mark; property: "opacity"; from: 1.0; to: 0.4; duration: 700; easing.type: Easing.InOutQuad }
    NumberAnimation { target: mark; property: "opacity"; from: 0.4; to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
    onRunningChanged: if (!running) mark.opacity = 1
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.recording
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)
  }
}
