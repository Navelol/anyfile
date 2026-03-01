import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: sidebar
    color: root.surface
    clip: true

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: root.border
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item { height: 16 }

        Text {
            Layout.leftMargin: 16
            text: "FORMATS"
            font.pixelSize: 10
            font.bold: true
            font.family: "monospace"
            font.letterSpacing: 2
            color: root.textDim
        }

        Item { height: 12 }

        ListView {
            id: groupList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: bridge.allFormatsGrouped()
            spacing: 0

            delegate: Column {
                width: parent ? parent.width : 0
                spacing: 0

                // Group header
                Item {
                    width: parent.width
                    height: 30
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        spacing: 8
                        Text {
                            text: modelData.icon
                            font.pixelSize: 13
                        }
                        Text {
                            text: modelData.name
                            font.pixelSize: 12
                            font.bold: true
                            font.family: "monospace"
                            color: root.textMid
                        }
                    }
                }

                // Ext tags
                Flow {
                    width: parent.width - 16
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    spacing: 4

                    Repeater {
                        model: modelData.exts
                        Rectangle {
                            width: extText.implicitWidth + 10
                            height: 20
                            color: root.surfaceHi
                            radius: 2

                            Text {
                                id: extText
                                anchors.centerIn: parent
                                text: "." + modelData
                                font.pixelSize: 10
                                font.family: "monospace"
                                color: root.textDim
                            }
                        }
                    }
                }

                Item { height: 10 }
            }
        }
    }
}
