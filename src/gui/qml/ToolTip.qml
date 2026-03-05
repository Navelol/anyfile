import QtQuick
import QtQuick.Controls.Basic

ToolTip {
    id: control

    delay: 400
    timeout: 6000

    contentItem: Text {
        text: control.text
        font.pixelSize: 11
        font.family: root.appFont
        color: root.textPrim
        wrapMode: Text.WordWrap
    }

    background: Rectangle {
        color: root.surfaceHi
        radius: 6
        border.color: root.border
        border.width: 1

        // Subtle drop shadow via outer glow rectangle
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: 7
            color: "transparent"
            border.color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            z: -1
        }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80; easing.type: Easing.InCubic }
    }
}
