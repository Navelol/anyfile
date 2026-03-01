import QtQuick
import QtQuick.Controls

Rectangle {
    id: btn
    width: contentText.implicitWidth + 24
    height: 30
    radius: 0
    color: ma.containsMouse ? root.surfaceHi : "transparent"
    border.color: active ? root.accent : (ma.containsMouse ? root.border : "transparent")
    border.width: 1

    property string text: ""
    property bool active: false

    signal clicked()

    Text {
        id: contentText
        anchors.centerIn: parent
        text: btn.text
        font.pixelSize: 11
        font.bold: true
        font.family: "monospace"
        font.letterSpacing: 1
        color: btn.active ? root.accent : root.textDim
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
