import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: header
    height: 52

    property bool showFormats: false

    signal formatsToggled()

    Rectangle {
        anchors.fill: parent
        color: root.surface
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: root.border
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 16
        spacing: 0

        // Logo / wordmark
        Row {
            spacing: 0
            Text {
                text: "ANYFILE"
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 3
                color: root.textPrim
                font.family: "monospace"
            }
            Text {
                text: "_"
                font.pixelSize: 18
                font.bold: true
                color: root.accent
                font.family: "monospace"
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Formats toggle
        HeaderButton {
            text: "FORMATS"
            active: header.showFormats
            onClicked: header.showFormats = !header.showFormats
        }

        Item { width: 8 }

        // About/Help
        HeaderButton {
            text: "?"
            width: 36
            onClicked: aboutDialog.open()
        }
    }

    // ── About dialog ─────────────────────────────────────────────────────────
    Dialog {
        id: aboutDialog
        title: ""
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 360

        background: Rectangle {
            color: root.surfaceHi
            border.color: root.border
            border.width: 1
        }

        ColumnLayout {
            width: parent.width
            spacing: 16

            Text {
                text: "ANYFILE_"
                font.pixelSize: 22
                font.bold: true
                font.family: "monospace"
                color: root.accent
                letterSpacing: 2
            }
            Text {
                text: "Universal File Converter · v0.1"
                font.pixelSize: 13
                color: root.textMid
            }
            Rectangle { height: 1; width: parent.width; color: root.border }
            Text {
                wrapMode: Text.WordWrap
                width: parent.width
                text: "Converts images, video, audio, 3D models, documents, archives, ebooks and data formats.\n\nDrag & drop a file or use the file picker to get started."
                font.pixelSize: 13
                color: root.textDim
                lineHeight: 1.5
            }
            Button {
                text: "CLOSE"
                Layout.alignment: Qt.AlignRight
                onClicked: aboutDialog.close()
                background: Rectangle {
                    color: parent.pressed ? root.accentDim : root.accent
                    radius: 0
                }
                contentItem: Text {
                    text: parent.text
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                    color: "#0e0e0f"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                width: 80
                height: 32
            }
        }
    }
}
