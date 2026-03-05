import QtQuick
import QtQuick.Effects

Item {
    property url   source
    property color color: "#ffffff"

    Image {
        id: img
        anchors.fill: parent
        source: parent.source
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        sourceSize.width:  512
        sourceSize.height: 512
        visible: false

        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(512, 512)
    }

    MultiEffect {
        source: img
        anchors.fill: img
        brightness: 1.0
        colorization: 1.0
        colorizationColor: parent.color
        autoPaddingEnabled: false
    }
}
