import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: zone

    property string outputPath:     ""
    property var    formats:        []
    property string selectedFormat: ""
    property bool   enabled:        false

    signal formatSelected(string fmt)
    signal browseClicked()

    color: root.surface
    border.color: enabled ? root.border : root.border
    border.width: 1
    radius: 8
    opacity: enabled ? 1.0 : 0.4

    // Label tag
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: -1
        anchors.left: parent.left
        anchors.leftMargin: 16
        color: root.surface
        width: labelText.implicitWidth + 12
        height: 18
        Text {
            id: labelText
            anchors.centerIn: parent
            text: "OUTPUT"
            font.pixelSize: 9
            font.bold: true
            font.family: root.appFont
            font.letterSpacing: 2
            color: root.textDim
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Format chips scroll area
        Item {
            Layout.fillWidth: true
            height: 38

            Text {
                visible: !zone.enabled
                anchors.centerIn: parent
                text: "Select an input file first"
                font.pixelSize: 12
                font.family: root.appFont
                color: root.textDim
            }

            // Horizontal scrollable format list
            Item {
                anchors.fill: parent
                visible: zone.enabled && zone.formats.length > 0
                clip: true

                Flickable {
                    id: zoneFlick
                    anchors.fill: parent
                    contentWidth: zoneRow.implicitWidth
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    Row {
                        id: zoneRow
                        y: (parent.height - height) / 2; spacing: 6
                        Repeater {
                            model: zone.formats
                            Rectangle {
                                id: chip
                                width: chipText.implicitWidth + 16; height: 30; radius: 8
                                color: zone.selectedFormat === modelData
                                       ? root.accent : (chipMa.containsMouse ? root.surfaceHi : root.surface)
                                border.color: zone.selectedFormat === modelData ? root.accent : root.border
                                border.width: 1
                                Text {
                                    id: chipText; anchors.centerIn: parent; text: "." + modelData
                                    font.pixelSize: 12; font.family: root.appFont
                                    font.bold: zone.selectedFormat === modelData
                                    color: zone.selectedFormat === modelData ? "#0e0e0f" : root.textMid
                                }
                                MouseArea {
                                    id: chipMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: zone.formatSelected(modelData)
                                }
                            }
                        }
                    }
                }
                AppScrollBar {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 4; orientation: Qt.Horizontal; flickable: zoneFlick
                }
            }
        }

        // Output path row
        RowLayout {
            Layout.fillWidth: true
            visible: zone.enabled && zone.outputPath !== ""
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: zone.outputPath
                font.pixelSize: 10
                font.family: root.appFont
                color: root.textDim
                elide: Text.ElideLeft
            }

            Rectangle {
                width: 26
                height: 26
                color: browseMa.containsMouse ? root.surfaceHi : "transparent"
                border.color: root.border
                border.width: 1
                radius: 6

                Text {
                    anchors.centerIn: parent
                    text: "…"
                    font.pixelSize: 13
                    color: root.textMid
                }

                MouseArea {
                    id: browseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: zone.browseClicked()
                }
            }
        }

        // No formats available
        Text {
            visible: zone.enabled && zone.formats.length === 0
            text: "No conversion targets available"
            font.pixelSize: 12
            font.family: root.appFont
            color: root.warnClr
        }
    }
}
