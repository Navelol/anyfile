import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.platform as Platform

Item {
    id: panel

    // ── State ─────────────────────────────────────────────────────────────────
    property string inputFilePath:   ""
    property string outputFilePath:  ""
    property string inputFormatExt:  ""
    property string selectedOutput:  ""
    property var    availableFormats: []

    function setInputFile(path) {
        inputFilePath  = path
        inputFormatExt = bridge.detectFormat(path)
        availableFormats = bridge.formatsFor(path)
        selectedOutput = availableFormats.length > 0 ? availableFormats[0] : ""
        outputFilePath = selectedOutput.length > 0
            ? bridge.suggestOutputPath(path, selectedOutput)
            : ""
        resultPanel.hide()
    }

    function doConvert() {
        if (!inputFilePath || !outputFilePath || bridge.converting) return
        bridge.convertFile(inputFilePath, outputFilePath, buildOptions())
    }

    function buildOptions() {
        var opts = {}
        if (advPanel.videoCodec.length  > 0) opts["videoCodec"]   = advPanel.videoCodec
        if (advPanel.audioCodec.length  > 0) opts["audioCodec"]   = advPanel.audioCodec
        if (advPanel.videoBitrate.length> 0) opts["videoBitrate"] = advPanel.videoBitrate
        if (advPanel.audioBitrate.length> 0) opts["audioBitrate"] = advPanel.audioBitrate
        if (advPanel.resolution.length  > 0) opts["resolution"]   = advPanel.resolution
        if (advPanel.framerate.length   > 0) opts["framerate"]    = advPanel.framerate
        if (advPanel.crfValue.length    > 0) opts["crf"]          = parseInt(advPanel.crfValue)
        return opts
    }

    // ── File pickers ──────────────────────────────────────────────────────────
    Platform.FileDialog {
        id: inputFilePicker
        title: "Select input file"
        fileMode: Platform.FileDialog.OpenFile
        onAccepted: panel.setInputFile(bridge.urlToPath(file.toString()))
    }

    Platform.FileDialog {
        id: outputFilePicker
        title: "Save output file as"
        fileMode: Platform.FileDialog.SaveFile
        onAccepted: panel.outputFilePath = bridge.urlToPath(file.toString())
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 0

        // ── Drop zone + format arrow ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // Input file zone
            DropZone {
                id: inputZone
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                hasFile: panel.inputFilePath !== ""
                fileName: panel.inputFilePath !== "" ? panel.inputFilePath.split("/").pop().split("\\").pop() : ""
                formatExt: panel.inputFormatExt
                label: "INPUT"
                placeholderIcon: "📂"
                placeholderText: "Drop file here or click to browse"
                onClicked: inputFilePicker.open()
            }

            // Arrow
            Column {
                spacing: 6
                Layout.preferredWidth: 48
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "→"
                    font.pixelSize: 28
                    color: panel.inputFilePath !== "" ? root.accent : root.border
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "TO"
                    font.pixelSize: 9
                    font.family: root.appFont
                    font.letterSpacing: 2
                    color: root.textDim
                }
            }

            // Output zone
            OutputZone {
                id: outputZone
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                outputPath: panel.outputFilePath
                formats: panel.availableFormats
                selectedFormat: panel.selectedOutput
                enabled: panel.inputFilePath !== ""
                onFormatSelected: function(fmt) {
                    panel.selectedOutput = fmt
                    panel.outputFilePath = bridge.suggestOutputPath(panel.inputFilePath, fmt)
                }
                onBrowseClicked: outputFilePicker.open()
            }
        }

        Item { height: 20 }

        // ── Advanced options (collapsible) ────────────────────────────────────
        AdvancedPanel {
            id: advPanel
            Layout.fillWidth: true
            visible: panel.inputFilePath !== ""
        }

        Item { height: 20 }

        // ── Convert button ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            height: 52
            visible: panel.inputFilePath !== ""

            Rectangle {
                id: convertBtn
                anchors.left: parent.left
                width: 200
                height: parent.height
                radius: 8
                color: {
                    if (bridge.converting) return root.border
                    if (btnMa.containsMouse) return root.accentDim
                    return root.accent
                }
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: bridge.converting ? "converting..." : "convert →"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: root.appFont
                    font.letterSpacing: 2
                    color: bridge.converting ? root.textDim : "#0e0e0f"
                }

                MouseArea {
                    id: btnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: bridge.converting ? Qt.WaitCursor : Qt.PointingHandCursor
                    onClicked: panel.doConvert()
                }
            }

            // Output path display
            Text {
                anchors.left: convertBtn.right
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - convertBtn.width - 16
                text: panel.outputFilePath
                font.pixelSize: 11
                font.family: root.appFont
                color: root.textDim
                elide: Text.ElideLeft
            }
        }

        Item { Layout.fillHeight: true }
    }
}
