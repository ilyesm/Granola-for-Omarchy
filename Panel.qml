import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ilyesm.granola"
  ipcTarget: "ilyesm.granola"

  property Item panelAnchor: null
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
  readonly property var nextEvent: granola.nextEvent
  readonly property string heroMeta: {
    if (!granola.installed) return "Not installed"
    if (granola.recording) return "Recording"
    if (nextEvent && nextEvent.when) return nextEvent.when
    if (granola.running) return granola.loggedIn ? "Open" : "Sign in"
    return granola.loggedIn ? "Ready" : "Installed"
  }
  readonly property string toggleHint: {
    if (!granola.installed) return "Install Granola"
    if (granola.recording) return "Recording — click to open Granola"
    return "Start recording"
  }
  readonly property string tooltipText: {
    if (granola.recording) return "Recording"
    if (nextEvent && nextEvent.title) {
      var when = nextEvent.when ? " · " + nextEvent.when : ""
      return nextEvent.title + when
    }
    return granola.statusText
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    granola.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
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
            title: nextEvent && nextEvent.title ? nextEvent.title : "Granola"
            meta: root.heroMeta
            detail: granola.recording ? "Listening" : (granola.version !== "" ? "Electron " + granola.version : "")
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
            text: "Granola is not installed. Press I or use the button below — the installer downloads the macOS app and rebuilds it for Linux."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: granola.installed
            width: parent.width
            text: granola.recording
              ? "Capturing microphone audio. Flip the switch to jump back to Granola."
              : "Flip the switch or press N to start a recording."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: granola.installed
              ? "N record  ·  O open  ·  R refresh"
              : "I install  ·  R refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
