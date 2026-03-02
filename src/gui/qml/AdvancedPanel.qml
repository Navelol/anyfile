import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Column {
    id: adv
    spacing: 0

    // Exposed properties
    property string videoCodec:   ""
    property string audioCodec:   ""
    property string videoBitrate: ""
    property string audioBitrate: ""
    property string resolution:   ""
    property string framerate:    ""
    property string crfValue:     ""
    property bool   forceOverwrite: false

    // Expand/collapse toggle
    Item {
        width: parent.width
        height: 32

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: root.border
        }

        Rectangle {
            anchors.centerIn: parent
            color: root.bg
            width: toggleRow.implicitWidth + 16
            height: 24

            Row {
                id: toggleRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: adv.expanded ? "▲" : "▼"
                    font.pixelSize: 9
                    color: root.textDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ADVANCED OPTIONS"
                    font.pixelSize: 9
                    font.bold: true
                    font.family: root.appFont
                    font.letterSpacing: 2
                    color: root.textDim
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: adv.expanded = !adv.expanded
            }
        }
    }

    property bool expanded: false

    // Options grid
    Item {
        width: parent.width
        height: adv.expanded ? optGrid.implicitHeight + 20 : 0
        clip: true
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        GridLayout {
            id: optGrid
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            columns: 4
            columnSpacing: 12
            rowSpacing: 8

            Repeater {
                model: [
                    { label: "Video Codec",    hint: "libx264, hevc_nvenc", prop: "videoCodec"   },
                    { label: "Audio Codec",    hint: "aac, libopus",        prop: "audioCodec"   },
                    { label: "Video Bitrate",  hint: "2M, 500k",            prop: "videoBitrate" },
                    { label: "Audio Bitrate",  hint: "192k, 320k",          prop: "audioBitrate" },
                    { label: "Resolution",     hint: "1920x1080",           prop: "resolution"   },
                    { label: "Framerate",      hint: "24, 30, 60",          prop: "framerate"    },
                    { label: "CRF Quality",    hint: "0–51",                prop: "crfValue"     },
                ]

                ColumnLayout {
                    spacing: 4

                    Text {
                        text: modelData.label
                        font.pixelSize: 10
                        font.family: root.appFont
                        color: root.textDim
                        font.letterSpacing: 0.5
                    }

                    Rectangle {
                        width: 170
                        height: 28
                        color: root.surfaceHi
                        border.color: fieldInput.activeFocus ? root.accent : root.border
                        border.width: 1
                        radius: 7

                        TextInput {
                            id: fieldInput
                            anchors.fill: parent
                            anchors.margins: 6
                            font.pixelSize: 12
                            font.family: root.appFont
                            color: root.textPrim
                            onTextChanged: adv[modelData.prop] = text

                            Text {
                                anchors.fill: parent
                                text: modelData.hint
                                font: parent.font
                                color: root.textDim
                                visible: parent.text.length === 0 && !parent.activeFocus
                            }
                        }
                    }
                }
            }

            // Force overwrite toggle (spans 1 column, sits naturally in the grid)
            ColumnLayout {
                spacing: 4
                Text {
                    text: "Force Overwrite"
                    font.pixelSize: 10
                    font.family: root.appFont
                    color: root.textDim
                    font.letterSpacing: 0.5
                }
                Rectangle {
                    width: 170; height: 28; radius: 7
                    color: adv.forceOverwrite ? "#3a2020" : root.surfaceHi
                    border.color: adv.forceOverwrite ? root.errorClr : root.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle {
                            width: 12; height: 12; radius: 3
                            color: adv.forceOverwrite ? root.errorClr : "transparent"
                            border.color: adv.forceOverwrite ? root.errorClr : root.textDim
                            border.width: 1.5
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }
                        Text {
                            text: adv.forceOverwrite ? "on — files will be replaced" : "off — ask before replacing"
                            font.pixelSize: 11; font.family: root.appFont
                            color: adv.forceOverwrite ? root.errorClr : root.textDim
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: adv.forceOverwrite = !adv.forceOverwrite
                    }
                }
            }
        }
    }
}
