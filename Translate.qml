import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// carlos.translate — quick translate overlay for SUPER+T.
//
// Modern theme-integrated UI:
// - Dynamic palette binding to Omarchy theme tokens (Color & Style singletons)
// - Polished header with quick shortcut badge and smooth close action
// - Language bar with animated 180° swap button and readable language labels
// - Input card with clear button, helper hints, and real-time character counter
// - Output card with visual "Copied!" feedback and detected language pill badge
// - High-contrast, responsive primary action button
//
// Summon with: omarchy-shell shell toggle carlos.translate
// Prefill with: omarchy-shell shell summon carlos.translate '{"text":"hello","source":"es","target":"en"}'
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string sourceLang: "auto"
  property string targetLang: "en"
  property string engine: "online"
  property string translatedText: ""
  property string detectedSource: ""
  property bool isLoading: false
  property string errorText: ""
  property bool copySuccess: false
  property real swapRotation: 0

  readonly property string helper: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/carlos.translate/bin/translate"

  readonly property string ocrHelper: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/carlos.translate/bin/ocr-text"

  property int contentMargin: Style.space(20)
  property int contentSpacing: Style.space(12)
  property int cardRadius: Math.max(16, Style.cornerRadius + 4)
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int maxInputChars: 500

  readonly property var langOptions: [
    { value: "en", label: "English" },
    { value: "es", label: "Spanish" },
    { value: "pt", label: "Portuguese" },
    { value: "fr", label: "French" },
    { value: "de", label: "German" },
    { value: "it", label: "Italian" },
    { value: "ja", label: "Japanese" },
    { value: "zh-CN", label: "Chinese (Simplified)" },
    { value: "ko", label: "Korean" },
    { value: "ru", label: "Russian" },
    { value: "ar", label: "Arabic" },
    { value: "hi", label: "Hindi" },
    { value: "tr", label: "Turkish" },
    { value: "nl", label: "Dutch" },
    { value: "pl", label: "Polish" },
    { value: "sv", label: "Swedish" },
    { value: "uk", label: "Ukrainian" }
  ]

  readonly property var sourceOptions: [{ value: "auto", label: "Auto detect" }].concat(langOptions)

  readonly property var engineOptions: [
    { value: "online", label: "Online" },
    { value: "offline", label: "Offline" }
  ]

  function langLabel(code) {
    if (!code) return ""
    var c = String(code).trim().toLowerCase()
    if (c === "auto" || c === "autodetect") return "Auto detect"
    var base = c.split("-")[0]
    for (var i = 0; i < langOptions.length; i++) {
      var optVal = langOptions[i].value.toLowerCase()
      if (optVal === c || optVal === base) {
        return langOptions[i].label
      }
    }
    return code
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    if (payload.target) root.targetLang = String(payload.target)
    if (payload.source) root.sourceLang = String(payload.source)
    if (payload.engine) root.engine = String(payload.engine)
    root.opened = true
    root.translatedText = ""
    root.detectedSource = ""
    root.errorText = ""
    root.isLoading = false
    root.copySuccess = false
    if (payload.text) {
      inputArea.text = String(payload.text)
      Qt.callLater(function() {
        if (root.opened) root.doTranslate()
      })
    }
    Qt.callLater(function() {
      if (root.opened) inputArea.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    if (transProc.running) transProc.running = false
    root.isLoading = false
    root.copySuccess = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "carlos.translate")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function swapLangs() {
    var oldSource = root.sourceLang
    var oldTarget = root.targetLang
    root.sourceLang = oldTarget
    root.targetLang = oldSource === "auto" ? "en" : oldSource
    root.swapRotation += 180

    // If there is already translated output, swap input with output and retranslate
    if (root.translatedText !== "" && !root.isLoading) {
      inputArea.text = root.translatedText
      root.translatedText = ""
      root.errorText = ""
      root.doTranslate()
    }
  }

  function doTranslate() {
    var q = String(inputArea.text || "").trim()
    if (q === "" || root.isLoading) return
    root.isLoading = true
    root.errorText = ""
    root.translatedText = ""
    root.detectedSource = ""
    root.copySuccess = false
    transProc.command = [root.helper, "--to", root.targetLang, "--from", root.sourceLang, "--engine", root.engine, q]
    transProc.running = true
  }

  function applyResult(payload) {
    root.isLoading = false
    var data = null
    try { data = JSON.parse(payload || "{}") } catch (e) { data = null }
    if (!data || data.ok !== true) {
      root.errorText = (data && data.error) ? String(data.error) : "translation failed"
      return
    }
    root.translatedText = String(data.translated || "")
    root.detectedSource = String(data.source || "")
  }

  function copyResult() {
    if (!root.translatedText) return
    Quickshell.execDetached(["wl-copy", root.translatedText])
    root.copySuccess = true
    copyFeedbackTimer.restart()
  }

  // OCR a screen region into the input: hide the overlay so the region
  // picker sees the desktop, then come back with the recognized text and
  // translate it. Cancelled/empty selections just reopen silently.
  function captureScreenText() {
    if (ocrProc.running) return
    root.close()
    ocrProc.running = true
  }

  function applyOcrText(payload) {
    var t = String(payload || "").trim()
    root.opened = true
    Qt.callLater(function() {
      if (!root.opened) return
      if (t !== "") {
        inputArea.text = t
        root.doTranslate()
      }
      inputArea.forceActiveFocus()
    })
  }

  Timer {
    id: copyFeedbackTimer
    interval: 1600
    repeat: false
    onTriggered: root.copySuccess = false
  }

  readonly property string outputText: {
    if (root.translatedText !== "") return root.translatedText
    if (root.isLoading) return "Translating…"
    if (root.errorText !== "") return root.errorText
    return ""
  }

  readonly property string outputMeta: {
    if (root.translatedText !== "" && root.sourceLang === "auto" && root.detectedSource !== "")
      return "Detected: " + root.langLabel(root.detectedSource) + (root.engine === "offline" ? " · offline" : "")
    if (root.translatedText !== "" && root.engine === "offline")
      return "offline"
    return ""
  }

  Process {
    id: transProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyResult(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (root.isLoading && exitCode !== 0) {
        root.isLoading = false
        if (root.errorText === "") root.errorText = "translator exited (" + exitCode + ")"
      }
    }
  }

  Process {
    id: ocrProc
    command: [root.ocrHelper]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyOcrText(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      // Collector already reopened on output; this covers silent exits.
      if (!root.opened) root.opened = true
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "carlos-translate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Fullscreen scrim backdrop
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    // Centered modal card
    Item {
      id: frame
      width: root.cardWidth
      height: Math.min(bodyCol.implicitHeight + root.contentMargin * 2,
        panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      Keys.onEscapePressed: root.dismiss()

      // Ambient accent glow
      Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: root.cardRadius + 4
        color: Color.accent
        opacity: 0.12
      }

      // Card body
      Rectangle {
        id: card
        anchors.fill: parent
        radius: root.cardRadius
        color: Color.menu.background
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
        border.width: 1

        MouseArea {
          anchors.fill: parent
          onClicked: {} // Prevent backdrop dismissal
        }

        Column {
          id: bodyCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: root.contentMargin
          spacing: root.contentSpacing

          // Header: Icon badge + Title + Shortcut pill + Close button
          Item {
            width: parent.width
            height: Style.space(34)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              // Icon badge
              Rectangle {
                width: Style.space(32)
                height: Style.space(32)
                radius: Style.space(8)
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "󰗊"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.heading
                }
              }

              // Title
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "Translate"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title + 2
                font.bold: true
              }

              // Shortcut pill
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(20)
                width: shortcutBadgeText.implicitWidth + Style.space(12)
                radius: Style.space(10)
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

                Text {
                  id: shortcutBadgeText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "SUPER+T"
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            // Close button
            Rectangle {
              id: closeBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              height: Style.space(28)
              radius: Style.space(14)
              color: closeHover.containsMouse ? Style.hoverFill : "transparent"
              border.color: closeHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15) : "transparent"
              border.width: 1

              Behavior on color { ColorAnimation { duration: 100 } }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "✕"
                color: closeHover.containsMouse ? Color.urgent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              MouseArea {
                id: closeHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
              }

              PanelToolTip {
                visible: closeHover.containsMouse
                text: "Close (Esc)"
                fontFamily: Style.font.family
              }
            }
          }

          // Subtle divider
          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          }

          // Language selectors: Source ⇄ Target
          Row {
            id: langRow
            width: parent.width
            spacing: Style.space(8)

            Dropdown {
              id: sourceDropdown
              width: Math.floor((parent.width - parent.spacing * 2 - swapBtn.width) / 2)
              label: ""
              showLabel: false
              fontFamily: Style.font.family
              foreground: Color.foreground
              background: Color.menu.background
              popupBorder: Color.popups.border
              options: root.sourceOptions
              value: root.sourceLang
              rowHeight: Style.space(34)
              popupRowHeight: Style.space(30)
              onChanged: function(v) { root.sourceLang = v }
            }

            // Circular Swap button with rotation animation
            Rectangle {
              id: swapBtn
              width: Style.space(34)
              height: Style.space(34)
              radius: Style.space(17)
              anchors.verticalCenter: parent.verticalCenter
              color: swapMouse.containsMouse ? Style.hoverFill : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              border.width: 1
              border.color: swapMouse.containsMouse ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

              Behavior on color { ColorAnimation { duration: 120 } }
              Behavior on border.color { ColorAnimation { duration: 120 } }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "⇄"
                color: swapMouse.containsMouse ? Color.accent : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title + 2
                rotation: root.swapRotation

                Behavior on rotation {
                  NumberAnimation { duration: 250; easing.type: Easing.OutBack }
                }
              }

              MouseArea {
                id: swapMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.swapLangs()
              }

              PanelToolTip {
                visible: swapMouse.containsMouse
                text: "Swap languages"
                fontFamily: Style.font.family
              }
            }

            Dropdown {
              id: targetDropdown
              width: Math.floor((parent.width - parent.spacing * 2 - swapBtn.width) / 2)
              label: ""
              showLabel: false
              fontFamily: Style.font.family
              foreground: Color.foreground
              background: Color.menu.background
              popupBorder: Color.popups.border
              options: root.langOptions
              value: root.targetLang
              rowHeight: Style.space(34)
              popupRowHeight: Style.space(30)
              onChanged: function(v) { root.targetLang = v }
            }
          }

          // Engine selector: online API vs on-device models.
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "Engine"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Dropdown {
              id: engineDropdown
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(160)
              label: ""
              showLabel: false
              fontFamily: Style.font.family
              foreground: Color.foreground
              background: Color.menu.background
              popupBorder: Color.popups.border
              options: root.engineOptions
              value: root.engine
              rowHeight: Style.space(30)
              popupRowHeight: Style.space(30)
              onChanged: function(v) { root.engine = v }
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.engine === "offline" ? "on-device models" : "free web API"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              opacity: 0.75
            }
          }

          // Source Input Box
          Rectangle {
            id: inputBox
            width: parent.width
            height: Style.space(136)
            radius: Style.cornerRadius + 4
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.035)
            border.color: inputArea.activeFocus
              ? Color.accent
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
            border.width: 1
            clip: true

            Behavior on border.color { ColorAnimation { duration: 150 } }

            ScrollView {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              anchors.bottomMargin: Style.space(30)
              clip: true
              ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

              TextArea {
                id: inputArea
                wrapMode: Text.WordWrap
                selectByMouse: true
                placeholderText: "Type or paste text to translate…"
                placeholderTextColor: Color.muted
                textFormat: Text.PlainText
                color: Color.foreground
                selectionColor: Style.selectionFill
                selectedTextColor: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                background: null
                Keys.onEscapePressed: root.dismiss()
                onTextChanged: {
                  if (text.length > root.maxInputChars) {
                    var cur = cursorPosition
                    Qt.callLater(function() {
                      inputArea.text = inputArea.text.slice(0, root.maxInputChars)
                      inputArea.cursorPosition = Math.min(cur, root.maxInputChars)
                    })
                  }
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (event.modifiers & Qt.ShiftModifier) {
                      // Shift+Enter inserts a newline
                    } else {
                      // Enter translates without clearing input
                      root.doTranslate()
                      event.accepted = true
                    }
                  }
                }
              }
            }

            // Bottom bar inside input card: Shortcut hint + Clear button + Counter
            Item {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(10)
              height: Style.space(20)

              // Shortcut hint
              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "↵ Translate  ·  Shift+↵ Newline"
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                opacity: 0.75
              }

              // Right side: Clear button + Counter
              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                // OCR from screen button
                Rectangle {
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  color: ocrHover.containsMouse ? Style.hoverFill : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰴑"
                    color: ocrHover.containsMouse ? Color.accent : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: ocrHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.captureScreenText()
                  }

                  PanelToolTip {
                    visible: ocrHover.containsMouse
                    text: "Capture text from screen"
                    fontFamily: Style.font.family
                  }
                }

                // Quick Clear button
                Rectangle {
                  visible: inputArea.text.length > 0
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  color: clearHover.containsMouse ? Style.hoverFill : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "✕"
                    color: clearHover.containsMouse ? Color.urgent : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: clearHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      inputArea.text = ""
                      inputArea.forceActiveFocus()
                    }
                  }

                  PanelToolTip {
                    visible: clearHover.containsMouse
                    text: "Clear text"
                    fontFamily: Style.font.family
                  }
                }

                // Character counter
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: inputArea.text.length + "/" + root.maxInputChars
                  color: inputArea.text.length >= root.maxInputChars ? Color.urgent
                       : (inputArea.text.length > root.maxInputChars * 0.9 ? Color.accent : Color.muted)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // Translation Output Box
          Rectangle {
            id: outputBox
            width: parent.width
            height: Style.space(120)
            radius: Style.cornerRadius + 4
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.035)
            border.color: root.errorText !== ""
              ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.4)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
            border.width: 1
            clip: true

            Behavior on border.color { ColorAnimation { duration: 150 } }

            ScrollView {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              anchors.rightMargin: Style.space(70) // room for copy button
              anchors.bottomMargin: Style.space(28) // room for status pills
              clip: true
              ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

              TextArea {
                id: outputArea
                wrapMode: Text.WordWrap
                readOnly: true
                selectByMouse: true
                placeholderText: "Translation will appear here…"
                placeholderTextColor: Color.muted
                textFormat: Text.PlainText
                text: root.outputText
                color: root.errorText !== "" ? Color.urgent : Color.foreground
                selectionColor: Style.selectionFill
                selectedTextColor: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                background: null
              }
            }

            // Copy button at top-right with "Copied!" pill animation
            Rectangle {
              id: copyBtn
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(10)
              width: root.copySuccess ? copyRow.implicitWidth + Style.space(14) : Style.space(28)
              height: Style.space(28)
              radius: Style.space(14)
              color: root.copySuccess
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                : (copyHover.containsMouse ? Style.hoverFill : "transparent")
              border.color: root.copySuccess
                ? Color.accent
                : (copyHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15) : "transparent")
              border.width: 1
              visible: root.translatedText !== ""

              Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 120 } }
              Behavior on border.color { ColorAnimation { duration: 120 } }

              Row {
                id: copyRow
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.copySuccess ? "󰄬" : "󰆏"
                  color: root.copySuccess ? Color.accent : (copyHover.containsMouse ? Color.foreground : Color.muted)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  visible: root.copySuccess
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Copied!"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              MouseArea {
                id: copyHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyResult()
              }

              PanelToolTip {
                visible: copyHover.containsMouse && !root.copySuccess
                text: "Copy translation"
                fontFamily: Style.font.family
              }
            }

            // Bottom info/status bar inside output card
            Item {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(10)
              height: Style.space(20)

              // Detected Language Pill
              Rectangle {
                visible: root.outputMeta !== ""
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(20)
                width: detectedText.implicitWidth + Style.space(14)
                radius: Style.space(10)
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                border.width: 1

                Row {
                  id: detectedText
                  anchors.centerIn: parent
                  spacing: Style.space(5)

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰗊"
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.outputMeta
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Loading indicator
              Row {
                visible: root.isLoading
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰑮"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  rotation: 0

                  NumberAnimation on rotation {
                    from: 0; to: 360; duration: 900; loops: Animation.Infinite
                    running: root.isLoading
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Translating…"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              // Error indicator
              Row {
                visible: root.errorText !== ""
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰅚"
                  color: Color.urgent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.errorText
                  color: Color.urgent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          // Full-width Primary Translate Button
          Rectangle {
            id: translateButton
            width: parent.width
            height: Style.space(42)
            radius: Style.cornerRadius + 2
            readonly property bool canTranslate: inputArea.text.trim().length > 0 && !root.isLoading
            opacity: canTranslate ? (translateHover.containsMouse ? 1.0 : 0.92) : 0.45

            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on color { ColorAnimation { duration: 120 } }

            color: canTranslate
              ? (translateHover.pressed ? Qt.darker(Color.accent, 1.15) : (translateHover.containsMouse ? Qt.lighter(Color.accent, 1.08) : Color.accent))
              : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)

            readonly property color onAccentColor: {
              var luma = Color.accent.r * 0.299 + Color.accent.g * 0.587 + Color.accent.b * 0.114
              return luma > 0.5 ? "#0e1017" : "#ffffff"
            }

            Row {
              anchors.centerIn: parent
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.isLoading ? "󰑮" : "󰗊"
                color: translateButton.canTranslate ? translateButton.onAccentColor : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body + 2
                rotation: 0

                NumberAnimation on rotation {
                  from: 0; to: 360; duration: 900; loops: Animation.Infinite
                  running: root.isLoading
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.isLoading ? "Translating…" : "Translate"
                color: translateButton.canTranslate ? translateButton.onAccentColor : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body + 1
                font.bold: true
              }

              Rectangle {
                visible: translateButton.canTranslate && !root.isLoading
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(18)
                width: enterBadge.implicitWidth + Style.space(10)
                radius: Style.space(4)
                color: Qt.rgba(translateButton.onAccentColor.r, translateButton.onAccentColor.g, translateButton.onAccentColor.b, 0.18)

                Text {
                  id: enterBadge
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "↵"
                  color: translateButton.onAccentColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            MouseArea {
              id: translateHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: translateButton.canTranslate ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                if (translateButton.canTranslate) root.doTranslate()
              }
            }
          }
        }
      }
    }
  }
}
