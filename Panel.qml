import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ilyesm.granola"
  ipcTarget: "ilyesm.granola"

  property Item panelAnchor: null
  property double nowMs: Date.now()
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: {
    if (granola.kind === "recording") return urgent
    if (!granola.installed) return Qt.darker(barForeground, 1.7)
    if (!granola.running) return Qt.darker(barForeground, 1.35)
    return barForeground
  }
  readonly property var featuredEvent: granola.nowEvent || granola.nextEvent
  readonly property var comingUp: granola.upcoming || []
  readonly property var hoverEvent: {
    // Prefer the next meeting that has not started. comingUp is the list
    // after that, so using it first skipped "what's next" when idle.
    if (granola.nextEvent && !granola.nextEvent.happening) return granola.nextEvent
    if (comingUp.length > 0) return comingUp[0]
    return granola.nowEvent || granola.nextEvent
  }
  readonly property string heroMeta: {
    if (!granola.installed) return "Not installed"
    if (granola.recording) return "Recording"
    if (granola.nowEvent) return "In a meeting"
    if (featuredEvent) return Model.relativeLabel(featuredEvent, nowMs)
    if (granola.running) return granola.loggedIn ? "Open" : "Sign in"
    return granola.loggedIn ? "Ready" : "Installed"
  }
  readonly property string toggleHint: {
    if (!granola.installed) return "Install Granola"
    if (granola.recording) return "Recording — click to open Granola"
    return "Start recording"
  }
  readonly property string tooltipText: {
    var event = hoverEvent
    var lines = []
    if (granola.recording) lines.push("Recording")
    if (event && event.title) {
      lines.push(event.title)
      var bits = []
      var rel = Model.relativeLabel(event, nowMs)
      if (rel && rel !== event.when) bits.push(rel)
      if (event.when) bits.push(event.when)
      if (event.location) bits.push(event.location)
      if (bits.length) lines.push(bits.join(" · "))
    }
    if (lines.length === 0) return granola.statusText || "Granola"
    return lines.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onTooltipTextChanged: if (button.tooltipHovered && root.bar) root.bar.showTooltip(button, tooltipText)

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    granola.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  Service {
    id: granola
    settings: root.settings
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltipText
    active: granola.kind === "recording"
    iconComponent: Component {
      Item {
        GranolaIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !granola.installed
          recording: granola.recording
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) granola.toggleRecording()
      else if (buttonCode === Qt.MiddleButton) granola.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.panelAnchor ? root.panelAnchor : button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, column.childrenRect.height) + Style.space(16))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      clip: true
      onActivateRequested: granola.toggleRecording()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "o" || t === "O") granola.openApp()
        else if (t === "n" || t === "N") granola.startRecording()
        else if (t === "i" || t === "I") granola.installApp()
        else if (t === "u" || t === "U") granola.updateApp()
        else if (t === "q" || t === "Q") granola.quitApp()
        else if (t === "r" || t === "R") granola.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(column.implicitHeight, column.childrenRect.height) + Style.space(16)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Granola"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: granola.running || granola.recording ? 1.0 : 0.55
            iconComponent: Component {
              GranolaIcon {
                iconSize: Style.font.display
                color: granola.recording ? root.urgent : root.foreground
                badgeColor: root.urgent
                crossed: !granola.installed
                recording: granola.recording
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: granola.installed
                checked: granola.recording
                busy: granola.busy
                foreground: hero.foreground
                onToggled: granola.toggleRecording()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: root.toggleHint
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          Text {
            visible: granola.actionStatus !== "" || granola.lastError !== ""
            width: parent.width
            text: granola.actionStatus !== "" ? granola.actionStatus : granola.lastError
            color: granola.lastError !== "" && granola.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !granola.installed
            width: parent.width
            text: "Granola is not installed. Press I to download the macOS app and rebuild it for Linux."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            visible: granola.installed && featuredEvent
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: granola.nowEvent ? "NOW" : "NEXT"
              foreground: granola.nowEvent ? root.urgent : root.foreground
              fontFamily: root.fontFamily
            }

            EventCard {
              width: parent.width
              event: featuredEvent
              featured: true
            }
          }

          Column {
            visible: granola.installed && comingUp.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            PanelSectionHeader {
              text: "COMING UP"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: comingUp
                EventCard {
                  required property var modelData
                  width: parent.width
                  event: modelData
                }
              }
            }
          }

          Text {
            visible: granola.installed && !featuredEvent && comingUp.length === 0
            width: parent.width
            text: "No upcoming meetings"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          PanelSeparator {
            visible: granola.installed
            width: parent.width
            foreground: root.foreground
          }

          CursorSurface {
            visible: granola.installed
            width: parent.width
            implicitHeight: openLabel.implicitHeight + Style.space(16)
            foreground: root.foreground

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: granola.openApp()
            }

            Text {
              id: openLabel
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: granola.running ? "Open Granola" : "Launch Granola"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          CursorSurface {
            visible: granola.installed && granola.updateAvailable
            width: parent.width
            implicitHeight: updateLabel.implicitHeight + Style.space(16)
            foreground: root.foreground

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: granola.updateApp()
            }

            Text {
              id: updateLabel
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: granola.latestVersion !== "" ? "Update to " + granola.latestVersion : "Update Granola"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Text {
            visible: granola.installed
            width: parent.width
            text: granola.updateAvailable ? "N record  ·  O open  ·  U update" : "N record  ·  O open"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            text: "Unofficial. Not affiliated with Granola, Inc."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component EventCard: CursorSurface {
    id: card
    property var event: null
    property bool featured: false

    foreground: root.foreground
    implicitHeight: eventColumn.implicitHeight + Style.space(featured ? 16 : 12)

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: granola.openApp()
    }

    Column {
      id: eventColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: event && event.title ? event.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: card.featured ? Style.font.body : Style.font.bodySmall
        font.bold: card.featured
        wrapMode: card.featured ? Text.WordWrap : Text.NoWrap
        elide: card.featured ? Text.ElideNone : Text.ElideRight
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: event && event.when ? event.when : ""
        color: event && event.happening ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: card.featured && event && (event.peopleLabel || event.location)
        text: {
          if (!event) return ""
          var parts = []
          if (event.peopleLabel) parts.push(event.peopleLabel)
          if (event.location) parts.push(event.location)
          return parts.join("  ·  ")
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
