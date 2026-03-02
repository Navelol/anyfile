import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Item {
    id: header
    height: 52

    // ── Drag-to-move & double-click-to-maximize ───────────────────────────────
    DragHandler {
        target: null
        onActiveChanged: if (active) root.startSystemMove()
    }
    TapHandler {
        onDoubleTapped: {
            if (root.visibility === Window.Maximized)
                root.showNormal()
            else
                root.showMaximized()
        }
    }

    property bool showFormats: false

    signal formatsToggled()

    Rectangle {
        anchors.fill: parent
        color: root.surface
        clip: true
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: root.border
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        // Horizontal wordmark (emblem + logotype baked into one crisp image)
        Image {
            source: "qrc:/icons/horizontal.png"
            Layout.preferredHeight: 26
            Layout.preferredWidth: implicitWidth * (26 / implicitHeight)
            fillMode: Image.PreserveAspectFit
            smooth: true
            antialiasing: true
        }

        Item { Layout.fillWidth: true }

        // Formats toggle
        HeaderButton {
            text: "formats"
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

        Item { width: 10 }
        Rectangle { width: 1; height: 18; color: root.border; opacity: 0.7 }
        Item { width: 6 }

        // ── Window controls ──────────────────────────────────────────────────
        // Minimize
        Rectangle {
            width: 30; height: 30; radius: 7; color: minMa.containsMouse ? root.surfaceHi : "transparent"
            Layout.alignment: Qt.AlignVCenter
            Behavior on color { ColorAnimation { duration: 100 } }
            Text {
                anchors.centerIn: parent; text: "\u2212"
                font.pixelSize: 14; font.weight: Font.Medium
                font.family: root.appFont; color: root.textDim
            }
            MouseArea { id: minMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showMinimized() }
        }
        Item { width: 2 }

        // Maximize / Restore
        Rectangle {
            width: 30; height: 30; radius: 7; color: maxMa.containsMouse ? root.surfaceHi : "transparent"
            Layout.alignment: Qt.AlignVCenter
            Behavior on color { ColorAnimation { duration: 100 } }
            Text {
                anchors.centerIn: parent
                text: root.visibility === Window.Maximized ? "\u2752" : "\u25A1"
                font.pixelSize: root.visibility === Window.Maximized ? 11 : 13
                font.weight: Font.Medium; font.family: root.appFont; color: root.textDim
            }
            MouseArea {
                id: maxMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }
        }
        Item { width: 2 }

        // Close
        Rectangle {
            width: 30; height: 30; radius: 7
            color: closeMa.containsMouse ? root.errorClr : "transparent"
            Layout.alignment: Qt.AlignVCenter
            Behavior on color { ColorAnimation { duration: 100 } }
            Text {
                anchors.centerIn: parent; text: "\u00D7"
                font.pixelSize: 16; font.weight: Font.Medium
                font.family: root.appFont
                color: closeMa.containsMouse ? "#fff" : root.textDim
            }
            MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
        }
        Item { width: 4 }
    }

    // ── About dialog ─────────────────────────────────────────────────────────
    Dialog {
        id: aboutDialog
        title: ""
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 360
        padding: 24
        topPadding: 24
        bottomPadding: 24

        background: Rectangle {
            color: root.surfaceHi
            border.color: root.border
            border.width: 1
            radius: 12
        }

        contentItem: ColumnLayout {
            spacing: 14
            width: aboutDialog.width - 48

            Row {
                spacing: 10
                Image {
                    source: "qrc:/icons/emblem.png"
                    width: 28; height: 28
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "anyfile"
                    font.pixelSize: 22
                    font.bold: true
                    font.family: root.appFont
                    color: root.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                text: "Universal File Converter · v0.1"
                font.pixelSize: 13
                font.family: root.appFont
                color: root.textMid
            }
            Rectangle { height: 1; Layout.fillWidth: true; color: root.border }
            Text {
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                text: "Converts images, video, audio, 3D models, documents, archives, ebooks and data formats.\n\nDrag & drop a file or use the file picker to get started."
                font.pixelSize: 13
                font.family: root.appFont
                color: root.textDim
                lineHeight: 1.5
            }
            Item { height: 4 }
            Rectangle {
                Layout.alignment: Qt.AlignRight
                width: closeLabel.implicitWidth + 28
                height: 34
                radius: 8
                color: closeBtnMa.containsMouse
                       ? (closeBtnMa.pressed ? root.accentDim : Qt.lighter(root.accent, 1.08))
                       : root.accent
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    id: closeLabel
                    anchors.centerIn: parent
                    text: "close"
                    font.pixelSize: 12
                    font.bold: true
                    font.family: root.appFont
                    color: "#0e0e0f"
                }
                MouseArea {
                    id: closeBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: aboutDialog.close()
                }
            }
        }
    }
}
