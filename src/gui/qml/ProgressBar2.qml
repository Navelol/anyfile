import QtQuick
import QtQuick.Controls

Item {
    id: bar
    height: 32

    property real   value:   0.0
    property string message: ""

    // Fake progress: smoothly animate toward 0.9 while converting,
    // then the real value=1.0 from the bridge snaps it to 100%.
    property real displayValue: 0.0

    // When real value jumps to 1.0 (done), honour it immediately.
    // When it resets to 0.0 (new conversion starting), snap displayValue back to 0.
    // Otherwise, let the fake timer drive displayValue forward.
    onValueChanged: {
        if (value <= 0.0) {
            displayValue = 0.0   // reset for next conversion
        } else if (value >= 1.0) {
            displayValue = 1.0
        } else if (value > displayValue) {
            displayValue = value
        }
    }

    Timer {
        id: fakeTimer
        interval: 400
        repeat: true
        running: bridge.converting && bar.displayValue < 0.9
        onTriggered: {
            // Slow logarithmic crawl — moves fast early, slows near 0.9
            var remaining = 0.9 - bar.displayValue
            bar.displayValue += remaining * 0.07
        }
    }

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
            width: parent.width * bar.displayValue
            color: Qt.rgba(0.91, 1, 0.35, 0.12)  // accent glow
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }

        // Accent line at fill edge
        Rectangle {
            x: parent.width * bar.displayValue - 1
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            color: root.accent
            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 16
            spacing: 12

            Text {
                visible: bar.displayValue > 0.0 || bridge.converting
                text: Math.round(bar.displayValue * 100) + "%"
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
