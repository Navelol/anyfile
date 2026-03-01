import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.platform as Platform
import Anyfile 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 860
    height: 640
    minimumWidth: 700
    minimumHeight: 540
    title: "anyfile"

    // ── Palette ───────────────────────────────────────────────────────────────
    readonly property color bg:        "#0e0e0f"
    readonly property color surface:   "#161618"
    readonly property color surfaceHi: "#1e1e21"
    readonly property color border:    "#2a2a2e"
    readonly property color accent:    "#e8ff5a"      // neon lime
    readonly property color accentDim: "#b0c43a"
    readonly property color textPrim:  "#f0f0f0"
    readonly property color textDim:   "#6b6b78"
    readonly property color textMid:   "#9999a8"
    readonly property color success:   "#4ade80"
    readonly property color errorClr:  "#ff5566"
    readonly property color warnClr:   "#fbbf24"

    FontLoader {
        id: manropeLoader
        source: "qrc:/fonts/Manrope-Regular.ttf"
    }
    readonly property string appFont: manropeLoader.status === FontLoader.Ready ? manropeLoader.name : "sans-serif"

    background: Rectangle { color: root.bg }

    // ── Backend bridge ────────────────────────────────────────────────────────
    ConverterBridge {
        id: bridge
        onConversionSucceeded: function(outPath, dur, inBytes, outBytes, warnings) {
            resultPanel.show(outPath, dur, inBytes, outBytes, warnings)
        }
        onConversionFailed: function(msg) {
            resultPanel.showError(msg)
        }
    }

    // ── Drag-and-drop overlay ─────────────────────────────────────────────────
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function(drop) {
            if (drop.urls.length > 0) {
                let path = bridge.urlToPath(drop.urls[0].toString())
                filePanel.setInputFile(path)
                dropOverlay.visible = false
            }
        }
        onEntered: dropOverlay.visible = true
        onExited:  dropOverlay.visible = false
    }

    Rectangle {
        id: dropOverlay
        anchors.fill: parent
        color: Qt.rgba(0.09, 0.09, 0.1, 0.92)
        visible: false
        z: 100
        border.color: root.accent
        border.width: 2
        radius: 12

        Column {
            anchors.centerIn: parent
            spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⬇"
                font.pixelSize: 52
                color: root.accent
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Drop file to convert"
                font.pixelSize: 18
                font.family: root.appFont
                color: root.textPrim
                font.letterSpacing: 2
            }
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        HeaderBar { id: header; Layout.fillWidth: true }

        // Main content
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── Format browser overlay (slides down from top) ─────────────────
            FormatBrowser {
                id: formatBrowser
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                z: 10
                opacity: header.showFormats ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // ── Conversion panel ──────────────────────────────────────────────
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                FilePanel {
                    id: filePanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                ResultPanel {
                    id: resultPanel
                    Layout.fillWidth: true
                }

                ProgressBar2 {
                    id: progressBar
                    Layout.fillWidth: true
                    visible: bridge.converting
                    value: bridge.progress
                    message: bridge.progressMessage
                }
            }
        }
    }
}
