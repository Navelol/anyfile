import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Overlay panel — positioned from parent (Main.qml anchors it below header)
Rectangle {
    id: panel

    property var  _groups:   bridge.allFormatsGrouped()
    property int  _sel:      -1   // -1 = show category grid

    // Height grows to fit content
    implicitHeight: inner.implicitHeight + 32
    radius: 12
    color: root.surfaceHi
    border.color: root.border
    border.width: 1
    clip: true

    // Subtle drop shadow underneath
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        z: -1
        radius: parent.radius + 1
        color: "transparent"
        border.color: Qt.rgba(0, 0, 0, 0.5)
        border.width: 6
    }

    ColumnLayout {
        id: inner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        spacing: 12

        // ── Top bar ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Back button (detail view only)
            Rectangle {
                visible: panel._sel >= 0
                width: 28; height: 28; radius: 8
                color: bkMa.containsMouse ? root.border : root.surface
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 13; color: root.textPrim; font.family: root.appFont }
                MouseArea { id: bkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel._sel = -1 }
            }

            Text {
                text: panel._sel < 0
                      ? "formats"
                      : panel._groups[panel._sel].name.toLowerCase() + "  ·  click any extension to copy path"
                font.pixelSize: 11
                font.bold: true
                font.family: root.appFont
                font.letterSpacing: 0.5
                color: root.textDim
            }

            Item { Layout.fillWidth: true }

            // Close button
            Rectangle {
                width: 28; height: 28; radius: 8
                color: closeMa.containsMouse ? root.border : root.surface
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 11; color: root.textDim; font.family: root.appFont }
                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: header.showFormats = false }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: root.border }

        // ── Category grid ─────────────────────────────────────────────────────
        Flow {
            visible: panel._sel < 0
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: panel._groups
                delegate: Rectangle {
                    id: catCard
                    width: catRow.implicitWidth + 24
                    height: 38
                    radius: 10
                    color: catMa.containsMouse ? root.border : root.surface
                    border.color: root.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Row {
                        id: catRow
                        anchors.centerIn: parent
                        spacing: 7
                        TintedIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16
                            source: modelData.icon
                            color: root.textMid
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name.toLowerCase()
                            font.pixelSize: 13
                            font.family: root.appFont
                            color: root.textPrim
                        }
                    }
                    MouseArea {
                        id: catMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel._sel = index
                    }
                }
            }
        }

        // ── Detail view ───────────────────────────────────────────────────────
        Item {
            visible: panel._sel >= 0
            Layout.fillWidth: true
            implicitHeight: Math.min(detailCol.implicitHeight, 340)
            clip: true

            Flickable {
                id: detailFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: detailCol.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                clip: true

                Column {
                    id: detailCol
                    width: detailFlick.width - (detailSB.visible ? detailSB.width + 4 : 0)
                    spacing: 10

                    Repeater {
                        model: panel._sel >= 0 ? panel._groups[panel._sel].exts : []
                        delegate: RowLayout {
                            property string srcExt: modelData
                            width: parent.width
                            spacing: 8

                            // Source ext badge
                            Rectangle {
                                width: srcLbl.implicitWidth + 16; height: 26; radius: 7
                                color: root.accent
                                Text {
                                    id: srcLbl; anchors.centerIn: parent; text: "." + srcExt
                                    font.pixelSize: 11; font.bold: true; font.family: root.appFont
                                    color: "#0e0e0f"
                                }
                            }

                            Text { text: "→"; font.pixelSize: 13; color: root.textDim; font.family: root.appFont }

                            // Target chips
                            Flow {
                                Layout.fillWidth: true; spacing: 5
                                Repeater {
                                    model: bridge.formatsFor("file." + srcExt)
                                    delegate: Rectangle {
                                        width: tgtLbl.implicitWidth + 14; height: 24; radius: 7
                                        color: root.surface; border.color: root.border; border.width: 1
                                        Text {
                                            id: tgtLbl; anchors.centerIn: parent; text: "." + modelData
                                            font.pixelSize: 10; font.family: root.appFont; color: root.textMid
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { height: 4 }
                }
            }

            AppScrollBar {
                id: detailSB
                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 4; orientation: Qt.Vertical; flickable: detailFlick
            }
        }

        Item { height: 4 }
    }
}
