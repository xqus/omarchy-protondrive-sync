import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "xqus.protondrive-sync"
  ipcTarget: "xqus.protondrive-sync"
  manageIpc: false

  property string focusSection: "header"
  property int rowIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: sync.active ? foreground : dim
  readonly property color barIconColor: sync.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string toggleHint: !sync.running ? "Start syncing" : (sync.paused ? "Resume syncing" : "Pause syncing")

  readonly property bool needsSetup: !sync.checked || !sync.ready
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"

  function ensureCursor() {
    if (needsSetup) {
      focusSection = "setup"
      rowIndex = 0
      return
    }
    if (sync.activity.length === 0) {
      focusSection = "header"
      rowIndex = 0
      return
    }
    if (focusSection !== "activity" && focusSection !== "header") focusSection = "activity"
    if (rowIndex >= sync.activity.length) rowIndex = Math.max(0, sync.activity.length - 1)
    if (rowIndex < 0) rowIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && sync.activity.length > 0) {
        focusSection = "activity"
        rowIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "activity") {
      if (dy < 0 && rowIndex === 0) {
        setHeaderCursor()
        return
      }
      rowIndex = Math.max(0, Math.min(sync.activity.length - 1, rowIndex + dy))
      scrollCursorIntoView()
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "setup") {
      if (sync.cliInstalled && !sync.authenticated) sync.login()
    } else if (focusSection === "header") {
      sync.toggleRunning()
    }
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "activity" && activityColumn && rowIndex >= 0 && rowIndex < activityColumn.children.length) {
      scrollItemIntoView(activityColumn.children[rowIndex])
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    sync.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onRowIndexChanged: scrollCursorIntoView()

  property bool settingsOpen: false

  function openSettings() {
    settingsOpen = true
    localFolderField.text = sync.localFolderRaw
    remoteFolderField.text = sync.remoteFolder
    pollSpin.value = sync.pollIntervalSec
    var idx = conflictCombo.find(sync.conflictStrategyLabel)
    conflictCombo.currentIndex = idx >= 0 ? idx : 0
  }

  function saveSettings() {
    if (localFolderField.text !== sync.localFolderRaw) sync.setSetting("localFolder", localFolderField.text)
    if (remoteFolderField.text !== sync.remoteFolder) sync.setSetting("remoteFolder", remoteFolderField.text)
    if (pollSpin.value !== sync.pollIntervalSec) sync.setSetting("pollIntervalSec", pollSpin.value)
    if (conflictCombo.currentText !== sync.conflictStrategyLabel) sync.setSetting("conflictStrategy", conflictCombo.currentText)
    settingsOpen = false
  }

  Service {
    id: sync
    settings: root.settings
    pluginId: root.moduleName
  }

  Connections {
    target: sync
    function onCheckedChanged() { root.ensureCursor() }
    function onActivityChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function syncNow(): string { sync.syncNow(); return "ok" }
    function refresh(): string { sync.refresh(); return "ok" }
    function debug(): string {
      return JSON.stringify({
        checked: sync.checked,
        cliInstalled: sync.cliInstalled,
        inotifyInstalled: sync.inotifyInstalled,
        authenticated: sync.authenticated,
        configured: sync.configured,
        ready: sync.ready,
        running: sync.running,
        paused: sync.paused,
        localFolder: sync.localFolder,
        remoteFolder: sync.remoteFolder,
        daemonPath: sync.daemonPath,
        lastError: sync.lastError
      })
    }
    function pause(): string { if (sync.running && !sync.paused) sync.toggleRunning(); return "ok" }
    function resume(): string { if (sync.running && sync.paused) sync.toggleRunning(); return "ok" }
    function status(): string { return sync.active ? "syncing" : (sync.paused ? "paused" : "stopped") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        ProtonSyncIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          opacity: sync.active ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) sync.syncNow()
      else if (buttonCode === Qt.MiddleButton) sync.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") sync.refresh()
        else if (t === "s" || t === "S") sync.syncNow()
        else if (t === "p" || t === "P") sync.toggleRunning()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            visible: !root.needsSetup
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Proton Drive Sync"
              meta: !sync.running ? "Not running"
                : (sync.paused ? "Paused" : ("Synced " + Model.relativeTime(sync.lastSyncTs)))
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: sync.active ? 1.0 : 0.5
              iconComponent: Component {
                ProtonSyncIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  checked: sync.active
                  busy: sync.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: sync.toggleRunning()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: sync.lastError !== ""
            width: parent.width
            text: sync.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          RowLayout {
            width: parent.width

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "Proton Drive Sync"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              visible: root.needsSetup && !root.settingsOpen
            }
            Item { Layout.fillWidth: true; visible: !(root.needsSetup && !root.settingsOpen) }

            PanelActionButton {
              iconText: root.settingsOpen ? "✕" : "⚙"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.settingsOpen ? (root.settingsOpen = false) : root.openSettings()
            }
          }

          // Settings form -- there is no generic settings GUI in Omarchy's
          // shell to defer to (the manifest schema is stored but never
          // rendered anywhere), so this writes directly through the same
          // setBarWidget shell IPC call `omarchy bar set` itself uses.
          ColumnLayout {
            visible: root.settingsOpen
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "SETTINGS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              text: "Local folder"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            TextField {
              id: localFolderField
              Layout.fillWidth: true
              placeholderText: "~/ProtonSync"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: "Proton Drive folder"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            TextField {
              id: remoteFolderField
              Layout.fillWidth: true
              placeholderText: "/my-files/Sync"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: "Remote poll interval (seconds)"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            SpinBox {
              id: pollSpin
              Layout.fillWidth: true
              from: 30
              to: 3600
              stepSize: 30
              editable: true
            }

            Text {
              text: "On conflict"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            ComboBox {
              id: conflictCombo
              Layout.fillWidth: true
              model: ["Keep both (rename)", "Prefer local", "Prefer remote"]
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.topMargin: Style.space(4)

              Text {
                Layout.fillWidth: true
                visible: sync.settingsBusy
                text: "Saving…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Item { Layout.fillWidth: true; visible: !sync.settingsBusy }

              Button {
                text: "Save"
                onClicked: root.saveSettings()
              }
            }
          }

          PanelSeparator {
            visible: root.settingsOpen
            foreground: root.foreground
          }

          // Setup: not installed / not logged in yet -- neither is fixable
          // from the settings form above, so this is shown independently
          // of it. Once both are true, "not configured" is handled by the
          // hint below instead, since the settings form is the actual fix.
          SetupRow {
            visible: !sync.cliInstalled || !sync.authenticated
            width: parent.width
          }

          Text {
            visible: sync.cliInstalled && sync.authenticated && !sync.configured && !root.settingsOpen
            width: parent.width
            textFormat: Text.PlainText
            text: "Click ⚙ above to set a local folder and a Proton Drive folder."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            visible: !root.needsSetup
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Local"; value: sync.localFolder }
            InfoPair { label: "Proton Drive"; value: sync.remoteFolder }
            InfoPair { label: "Tracked files"; value: String(sync.trackedFiles) }
          }

          PanelSeparator {
            visible: !root.needsSetup
            foreground: root.foreground
          }

          Column {
            visible: !root.needsSetup
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "RECENT ACTIVITY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: sync.activity.length === 0
              width: parent.width
              text: "Nothing synced yet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: activityColumn
              visible: sync.activity.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: sync.activity
                ActivityRow {
                  required property var modelData
                  required property int index
                  width: activityColumn.width
                  entry: modelData
                  rowIdx: index
                }
              }
            }
          }
        }
      }
    }
  }

  component SetupRow: CursorSurface {
    id: setupRow

    hasCursor: root.cursorActive && root.focusSection === "setup"
    foreground: root.foreground

    implicitHeight: setupRowLayout.implicitHeight + Style.spacing.rowPaddingX

    readonly property string title:
      !sync.cliInstalled ? "proton-drive CLI is not installed" : "Log in to Proton Drive"
    readonly property string subtitle:
      !sync.cliInstalled ? "Install it from proton.me/download/drive/cli, then reopen this panel"
      : "Opens proton-drive auth login in a browser"
    readonly property bool clickable: sync.cliInstalled && !sync.authenticated && !sync.busy

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: setupRow.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: setupRow.clickable
      onEntered: {
        root.cursorActive = true
        root.focusSection = "setup"
      }
      onClicked: sync.login()
    }

    RowLayout {
      id: setupRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: sync.busy ? "Logging in…" : setupRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: setupRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: setupRow.clickable
        iconText: "󰌋"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: setupRow.clickable
        Layout.alignment: Qt.AlignVCenter
        onClicked: sync.login()
      }
    }
  }

  component ActivityRow: CursorSurface {
    id: activityRow
    property var entry: null
    property int rowIdx: 0

    hasCursor: root.cursorActive && root.focusSection === "activity" && root.rowIndex === rowIdx
    foreground: root.foreground

    implicitHeight: activityContent.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.activityGlyph(activityRow.entry ? activityRow.entry.action : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: activityContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.activityLabel(activityRow.entry)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: activityRow.entry ? Model.relativeTime(activityRow.entry.ts) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
