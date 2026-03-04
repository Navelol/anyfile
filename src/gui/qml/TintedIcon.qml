import QtQuick
import QtQuick.Effects

Item {
    property url source
    property color color: "#ffffff"

    Image {
        id: img
        anchors.fill: parent
        source: parent.source
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        sourceSize.width: parent.width * 2
        sourceSize.height: parent.height * 2
        visible: false
    }

    MultiEffect {
        source: img
        anchors.fill: img
        brightness: 1.0
        colorization: 1.0
        colorizationColor: parent.color
    }
}
