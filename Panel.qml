import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// The Omarchy Windows VM in the bar, only while it is running.
//
// A widget for a VM that is off most of the day would be a permanent icon that
// means nothing; this one takes no space until the container exists. Once it
// does, the panel answers the two questions you have about a VM in the corner
// of your screen: how do I get back to it, and what is it costing me.
//
// Stats come from bin/winvm-sample, which reads the container's cgroup and the
// qemu process's /proc entry directly. That needs no privileges, so watching
// the VM never prompts; only stopping it does.
Panel {
  id: root
  moduleName: "blacksheep.winvm"
  ipcTarget: "blacksheep.winvm"

  readonly property string binDir:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/blacksheep.winvm/bin"

  readonly property int openInterval: Math.max(1000, setting("interval", 2) * 1000)
  readonly property int idleInterval: Math.max(2000, setting("idleInterval", 5) * 1000)

  property var sample: null
  property var prevSample: null
  property var d: Model.derive(null, null)

  // Stopping takes a while: Windows gets an ACPI shutdown and up to a couple
  // of minutes to act on it. Hold a visible "stopping" state until the
  // container is actually gone, so a second click doesn't look necessary.
  property bool stopping: false
  property bool confirmStop: false

  readonly property bool running: d.running

  visible: running
  implicitWidth: running ? button.implicitWidth : 0
  implicitHeight: running ? (bar ? bar.barSize : 26) : 0

  onRunningChanged: {
    if (!running) {
      stopping = false
      confirmStop = false
      close()
    }
  }

  function refresh() {
    if (sampleProc.running) return
    sampleProc.running = true
  }

  function applySample(text) {
    var next
    try {
      next = JSON.parse(String(text || "").trim() || "null")
    } catch (e) {
      return
    }
    if (!next) return
    next.__t = Date.now() / 1000
    prevSample = sample
    sample = next
    d = Model.derive(sample, prevSample)
  }

  function run(script) {
    Quickshell.execDetached([binDir + "/" + script])
  }

  function connect() {
    run("winvm-connect")
    close()
  }

  function openConsole() {
    Quickshell.execDetached(["xdg-open", "http://127.0.0.1:8006"])
    close()
  }

  function openShared() {
    Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/Windows"])
    close()
  }

  // Two clicks: shutting Windows down from a bar popup is too easy to do by
  // accident on the way to Connect.
  function requestStop() {
    if (stopping) return
    if (!confirmStop) {
      confirmStop = true
      confirmTimer.restart()
      return
    }
    confirmStop = false
    stopping = true
    run("winvm-stop")
  }

  Process {
    id: sampleProc
    command: [root.binDir + "/winvm-sample"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySample(text)
    }
  }

  Timer {
    interval: root.opened ? root.openInterval : root.idleInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: confirmTimer
    interval: 4000
    onTriggered: root.confirmStop = false
  }

  // If the stop was declined at the password prompt the VM stays up; don't
  // leave the panel claiming otherwise forever.
  Timer {
    running: root.stopping
    interval: 180000
    onTriggered: root.stopping = false
  }

  onOpenedChanged: if (opened) refresh()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  readonly property color hot: bar ? bar.urgent : Color.urgent

  readonly property string stateText: {
    if (stopping) return "Shutting down…"
    return (d.rdp ? "Connected" : "Running, not connected") + " · up " + Model.uptimeText(d.uptime)
  }

  readonly property string tooltipSummary: {
    if (!running) return ""
    return [
      "Windows VM — " + (stopping ? "shutting down" : (d.rdp ? "connected" : "running")),
      "CPU " + Model.percent(d.cpu) + " of " + d.vcpus + " vCPUs"
        + "   Mem " + Model.bytes(d.memBytes) + " / " + Model.bytes(d.ramBytes),
      "Disk " + Model.rateText(d.ioRead + d.ioWrite)
        + "   Net ↓ " + Model.rateText(d.netRx) + " ↑ " + Model.rateText(d.netTx)
    ].join("\n")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖳"
    tooltipText: root.tooltipSummary
    active: root.stopping
    useActiveColor: true
    activeColor: root.hot

    onPressed: function(b) {
      // Right-click is the shortcut for what you want most: the VM's window.
      if (b === Qt.RightButton) {
        root.connect()
        return
      }
      root.toggle()
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = String(t).toLowerCase()
        if (k === "c") root.connect()
        else if (k === "w") root.openConsole()
        else if (k === "f") root.openShared()
        else if (k === "s") root.requestStop()
        else if (k === "r") root.refresh()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          foreground: root.fg
          fontFamily: root.ff
          title: "Windows VM"
          meta: root.stateText
          iconOpacity: root.d.rdp ? 1.0 : 0.6
          iconComponent: Component {
            Text {
              text: "󰖳"
              textFormat: Text.PlainText
              color: root.stopping ? root.hot : root.fg
              font.family: root.ff
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { width: parent.width }

        // Each meter is measured against what the guest was given, which is
        // what tells you whether Windows itself is starved. The note puts it
        // against the host, which is what tells you what it is costing you.
        Column {
          width: parent.width
          spacing: Style.space(8)

          MeterRow {
            width: parent.width
            label: "CPU"
            value: root.d.cpu
            valueText: Model.percent(root.d.cpu)
            leading: root.d.cpu >= 0.9
            note: root.d.cpuCores.toFixed(1) + " of " + root.d.vcpus + " vCPUs · "
              + (root.d.cpuHost * 100).toFixed(1) + "% of host (" + root.d.hostCores + " threads)"
            foreground: root.fg
            fontFamily: root.ff
            hotColor: root.hot
          }

          // Host-side view: Windows zeroes its RAM at boot, so a running guest
          // holds nearly all of its allocation whatever Task Manager says.
          // This is what the VM takes from Linux, not what Windows is using,
          // so it gets no "near the limit" emphasis.
          MeterRow {
            width: parent.width
            label: "Memory"
            value: root.d.mem
            valueText: Model.bytes(root.d.memBytes)
            note: "held on host for a " + Model.bytes(root.d.ramBytes) + " guest · "
              + Model.percent(root.d.memHost) + " of host RAM"
            foreground: root.fg
            fontFamily: root.ff
            hotColor: root.hot
          }

          MeterRow {
            width: parent.width
            label: "Disk I/O"
            value: root.d.io
            valueText: Model.rateText(root.d.ioRead + root.d.ioWrite)
            note: "read " + Model.rateText(root.d.ioRead) + " · write " + Model.rateText(root.d.ioWrite)
            foreground: root.fg
            fontFamily: root.ff
            hotColor: root.hot
          }

          MeterRow {
            width: parent.width
            label: "Image"
            value: root.d.diskSize > 0 ? root.d.diskUsed / root.d.diskSize : 0
            valueText: Model.bytes(root.d.diskUsed)
            note: "written of a " + Model.bytes(root.d.diskSize) + " virtual disk"
            foreground: root.fg
            fontFamily: root.ff
            hotColor: root.hot
          }
        }

        PanelSeparator { width: parent.width }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(14)
          rowSpacing: Style.space(6)

          InfoLabel { text: "Network" }
          InfoValue {
            Layout.fillWidth: true
            text: "↓ " + Model.rateText(root.d.netRx) + "   ↑ " + Model.rateText(root.d.netTx)
          }

          InfoLabel { text: "Uptime" }
          InfoValue { text: Model.uptimeText(root.d.uptime) }

          InfoLabel { text: "Container" }
          InfoValue { text: root.d.container || "—" }
        }

        PanelSeparator { width: parent.width }

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Button {
            Layout.fillWidth: true
            bordered: true
            text: root.d.rdp ? "Focus" : "Connect"
            iconText: "󰢹"
            tooltipText: root.d.rdp ? "Bring the RDP window forward (c)" : "Open an RDP session (c)"
            enabled: !root.stopping
            foreground: root.fg
            fontFamily: root.ff
            fontSize: Style.font.bodySmall
            onClicked: root.connect()
          }

          Button {
            Layout.fillWidth: true
            bordered: true
            text: "Console"
            iconText: "󰖟"
            tooltipText: "Web console on :8006, for when RDP isn't up yet (w)"
            foreground: root.fg
            fontFamily: root.ff
            fontSize: Style.font.bodySmall
            onClicked: root.openConsole()
          }

          Button {
            Layout.fillWidth: true
            bordered: true
            text: "Shared"
            iconText: "󰉋"
            tooltipText: "~/Windows, which the guest sees as a network share (f)"
            foreground: root.fg
            fontFamily: root.ff
            fontSize: Style.font.bodySmall
            onClicked: root.openShared()
          }

          Button {
            Layout.fillWidth: true
            bordered: true
            text: root.stopping ? "Stopping" : (root.confirmStop ? "Confirm" : "Stop")
            iconText: "󰐥"
            iconSpinning: root.stopping
            tooltipText: "Shut Windows down and stop the container (s, twice)"
            enabled: !root.stopping
            foreground: root.confirmStop ? root.hot : root.fg
            fontFamily: root.ff
            fontSize: Style.font.bodySmall
            onClicked: root.requestStop()
          }
        }

        Text {
          width: parent.width
          text: "c connect · w console · f shared · s stop · right-click the icon to connect"
          textFormat: Text.PlainText
          elide: Text.ElideRight
          opacity: 0.45
          color: root.fg
          font.family: root.ff
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.fg
    opacity: 0.6
    font.family: root.ff
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.fg
    font.family: root.ff
    font.pixelSize: Style.font.bodySmall
  }
}
