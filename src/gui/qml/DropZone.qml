import QtQuick
import QtQuick.Controls

Rectangle {
    id: zone

    property bool   hasFile:         false
    property string fileName:        ""
    property string formatExt:       ""
    property string label:           "FILE"
    property string placeholderIcon: "qrc:/icons/dropzone.svg"
    property string placeholderText: "Drop or click"

    signal clicked()

    color: ma.containsMouse && !hasFile ? root.surfaceHi : root.surface
    border.color: hasFile ? root.accent : (ma.containsMouse ? root.textDim : root.border)
    border.width: hasFile ? 1 : 1
    radius: 8

    Behavior on border.color { ColorAnimation { duration: 150 } }

    // Label tag
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: -1
        anchors.left: parent.left
        anchors.leftMargin: 16
        color: hasFile ? root.accent : root.surface
        width: labelText.implicitWidth + 12
        height: 18

        Text {
            id: labelText
            anchors.centerIn: parent
            text: zone.label
            font.pixelSize: 9
            font.bold: true
            font.family: root.appFont
            font.letterSpacing: 2
            color: hasFile ? "#0e0e0f" : root.textDim
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: hasFile
            text: "✓"
            font.pixelSize: 28
            color: root.success
        }
        TintedIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !hasFile
            width: 40; height: 40
            source: zone.placeholderIcon
            color: root.textDim
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: hasFile ? zone.fileName : zone.placeholderText
            font.pixelSize: hasFile ? 13 : 12
            font.family: root.appFont
            color: hasFile ? root.textPrim : root.textDim
            width: zone.width - 32
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
        }

        // Format badge
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: zone.formatExt !== ""
            color: root.surfaceHi
            border.color: root.border
            width: fmtText.implicitWidth + 14
            height: 22
            radius: 8

            Text {
                id: fmtText
                anchors.centerIn: parent
                text: "." + zone.formatExt
                font.pixelSize: 11
                font.family: root.appFont
                color: root.accent
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: zone.clicked()
    }
}
