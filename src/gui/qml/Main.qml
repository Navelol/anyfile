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
    flags: Qt.FramelessWindowHint | Qt.Window

    // ── Palette ───────────────────────────────────────────────────────────────
    readonly property color bg:        "#0e0e0f"
    readonly property color surface:   "#161618"
    readonly property color surfaceHi: "#1e1e21"
    readonly property color border:    "#2a2a2e"
    readonly property color accent:    "#fed150"
    readonly property color accentDim: "#c9a53e"
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

    color: "transparent"
    background: Rectangle { color: "transparent" }

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

    // ── Frameless resize handles ───────────────────────────────────────────────
    // Edges
    Item {
        z: 999; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 5
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.LeftEdge) }
        HoverHandler { cursorShape: Qt.SizeHorCursor }
    }
    Item {
        z: 999; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 5
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.RightEdge) }
        HoverHandler { cursorShape: Qt.SizeHorCursor }
    }
    Item {
        z: 999; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 5
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.TopEdge) }
        HoverHandler { cursorShape: Qt.SizeVerCursor }
    }
    Item {
        z: 999; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 5
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.BottomEdge) }
        HoverHandler { cursorShape: Qt.SizeVerCursor }
    }
    // Corners
    Item {
        z: 999; anchors.left: parent.left; anchors.top: parent.top; width: 8; height: 8
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.LeftEdge | Qt.TopEdge) }
        HoverHandler { cursorShape: Qt.SizeFDiagCursor }
    }
    Item {
        z: 999; anchors.right: parent.right; anchors.top: parent.top; width: 8; height: 8
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.RightEdge | Qt.TopEdge) }
        HoverHandler { cursorShape: Qt.SizeBDiagCursor }
    }
    Item {
        z: 999; anchors.left: parent.left; anchors.bottom: parent.bottom; width: 8; height: 8
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.LeftEdge | Qt.BottomEdge) }
        HoverHandler { cursorShape: Qt.SizeBDiagCursor }
    }
    Item {
        z: 999; anchors.right: parent.right; anchors.bottom: parent.bottom; width: 8; height: 8
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden; onActiveChanged: if (active) root.startSystemResize(Qt.RightEdge | Qt.BottomEdge) }
        HoverHandler { cursorShape: Qt.SizeFDiagCursor }
    }

    // ── Rounded window frame (all visual content lives here) ─────────────────
    Rectangle {
        id: windowFrame
        anchors.fill: parent
        radius: 10
        clip: true
        color: root.bg
        border.color: root.border
        border.width: 1

        // ── Drag-and-drop overlay ─────────────────────────────────────────────
        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: function(drop) {
                for (var i = 0; i < drop.urls.length; i++)
                    filePanel.addFile(bridge.urlToPath(drop.urls[i].toString()))
                dropOverlay.visible = false
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
                    text: "Drop files to add"
                    font.pixelSize: 18
                    font.family: root.appFont
                    color: root.textPrim
                    font.letterSpacing: 2
                }
            }
        }

        // ── Layout ───────────────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            HeaderBar { id: header; Layout.fillWidth: true }

            // Main content
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── Format browser overlay (slides down from top) ─────────────
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

                // ── Conversion panel ──────────────────────────────────────────
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
                        visible: false
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
}
