import QtQuick
import QtQuick.Controls

Item {
    id: bar
    height: 32

    property real   value:   0.0
    property string message: ""

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: root.border
    }

    Rectangle {
        anchors.fill: parent
        color: root.surface

        // Animated fill
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * bar.value
            color: Qt.rgba(0.91, 1, 0.35, 0.12)  // accent glow
            Behavior on width { NumberAnimation { duration: 150 } }
        }

        // Accent line at fill edge
        Rectangle {
            x: parent.width * bar.value - 1
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            color: root.accent
            Behavior on x { NumberAnimation { duration: 150 } }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 16
            spacing: 12

            Text {
                text: Math.round(bar.value * 100) + "%"
                font.pixelSize: 11
                font.bold: true
                font.family: root.appFont
                color: root.accent
            }

            Text {
                text: bar.message
                font.pixelSize: 11
                font.family: root.appFont
                color: root.textDim
            }
        }
    }
}
