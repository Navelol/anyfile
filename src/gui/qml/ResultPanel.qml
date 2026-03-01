import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: panel
    height: visible ? content.implicitHeight + 1 : 0
    visible: false
    clip: true

    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    property bool  isSuccess:  true
    property string outPath:   ""
    property string statsText: ""
    property var    warningsList: []

    function show(outPath, dur, inBytes, outBytes, warnings) {
        panel.isSuccess  = true
        panel.outPath    = outPath

        function humanSize(b) {
            if (b < 1024) return b + " B"
            if (b < 1024*1024) return Math.round(b/1024) + " KB"
            return (b/(1024*1024)).toFixed(1) + " MB"
        }

        panel.statsText    = dur.toFixed(2) + "s  ·  " + humanSize(inBytes) + " → " + humanSize(outBytes)
        panel.warningsList = warnings
        panel.visible      = true
    }

    function showError(msg) {
        panel.isSuccess = false
        panel.outPath   = msg
        panel.statsText = ""
        panel.warningsList = []
        panel.visible   = true
    }

    function hide() { panel.visible = false }

    // Border at top
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: root.border
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.topMargin: 1
        width: parent.width
        padding: 16
        spacing: 8

        // Success / error row
        Row {
            spacing: 12
            width: parent.width - 32

            Rectangle {
                width: 28
                height: 28
                color: panel.isSuccess ? Qt.rgba(0.12, 0.9, 0.37, 0.12) : Qt.rgba(1, 0.2, 0.25, 0.12)
                radius: 0

                Text {
                    anchors.centerIn: parent
                    text: panel.isSuccess ? "✓" : "✗"
                    font.pixelSize: 14
                    font.bold: true
                    color: panel.isSuccess ? root.success : root.errorClr
                }
            }

            Column {
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: panel.isSuccess ? "Conversion complete" : "Conversion failed"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: "monospace"
                    color: panel.isSuccess ? root.success : root.errorClr
                }

                Text {
                    text: panel.outPath
                    font.pixelSize: 11
                    font.family: "monospace"
                    color: root.textMid
                    width: content.width - 32 - 28 - 12
                    elide: Text.ElideLeft
                }
            }
        }

        // Stats
        Text {
            visible: panel.isSuccess && panel.statsText !== ""
            text: panel.statsText
            font.pixelSize: 11
            font.family: "monospace"
            color: root.textDim
            leftPadding: 40
        }

        // Warnings
        Repeater {
            model: panel.warningsList
            Row {
                spacing: 8
                leftPadding: 40
                Text { text: "⚠"; font.pixelSize: 11; color: root.warnClr }
                Text {
                    text: modelData
                    font.pixelSize: 11
                    font.family: "monospace"
                    color: root.warnClr
                    wrapMode: Text.WordWrap
                    width: content.width - 32 - 40
                }
            }
        }
    }
}
