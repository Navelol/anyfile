import QtQuick
import QtQuick.Controls

// Pure click-only dropdown selector — no free-text input.
// Usage:
//   FieldDropdown { id: foo; options: ["aac","libopus"]; hint: "default" }
//   foo.setValue("aac")   — select programmatically (e.g. from a preset)
//   foo.value             — current selection ("" means nothing selected)
Rectangle {
    id: fd

    property string value:   ""
    property string hint:    "default"
    property var    options: []

    function setValue(v) { value = v }

    // Close when this item is hidden or destroyed
    onVisibleChanged: if (!visible) _popup.close()

    width: 170; height: 28; radius: 7
    color: btnMa.containsMouse ? root.border : root.surfaceHi
    border.color: (_popup.opened || btnMa.containsMouse) ? root.accent : root.border
    border.width: 1
    Behavior on color { ColorAnimation { duration: 80 } }

    Row {
        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6
        spacing: 0

        Text {
            width: parent.width - arrowLbl.width - 6
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: fd.value !== "" ? fd.value : fd.hint
            font.pixelSize: 12; font.family: root.appFont
            color: fd.value !== "" ? root.textPrim : root.textDim
            elide: Text.ElideRight
        }

        Text {
            id: arrowLbl
            anchors.verticalCenter: parent.verticalCenter
            text: _popup.opened ? "\u25b4" : "\u25be"
            font.pixelSize: 9; color: root.textDim
        }
    }

    MouseArea {
        id: btnMa; anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: _popup.opened ? _popup.close() : _popup.open()
    }

    Popup {
        id: _popup
        // Position below (or above) the trigger rectangle
        y: {
            var sceneY = fd.mapToItem(null, 0, 0).y
            var contentH = (fd.options.length + 1) * 26 + 10
            var openAbove = (sceneY + fd.height + 2 + contentH > fd.Window.height)
            return openAbove ? -(contentH + 2) : fd.height + 2
        }
        x: 0
        width: Math.max(fd.width, 160)
        height: contentCol.implicitHeight + 10
        padding: 0
        margins: 0

        background: Rectangle {
            radius: 7
            color: root.surfaceHi
            border.color: root.accent
            border.width: 1
        }

        // No background dim / overlay from Controls
        dim: false

        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 100; easing.type: Easing.OutCubic } }
        exit:  Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80;  easing.type: Easing.InCubic  } }

        Column {
            id: contentCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.topMargin: 5
            spacing: 0

            // "none / clear" row
            Rectangle {
                width: parent.width; height: 26; radius: 4
                color: clearMa.containsMouse ? root.border : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                Row {
                    anchors.fill: parent; anchors.leftMargin: 8
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "—"; font.pixelSize: 11; font.family: root.appFont
                        color: root.textDim; font.italic: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "none"; font.pixelSize: 11; font.family: root.appFont
                        color: root.textDim; font.italic: true
                    }
                }
                Rectangle {
                    visible: fd.value === ""
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6; radius: 3; color: root.accent
                }
                MouseArea {
                    id: clearMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { fd.value = ""; _popup.close() }
                }
            }

            Repeater {
                model: fd.options
                Rectangle {
                    width: parent.width; height: 26; radius: 4
                    color: optMa.containsMouse ? root.border : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 8
                        text: modelData; font.pixelSize: 11; font.family: root.appFont
                        color: root.textPrim
                    }
                    Rectangle {
                        visible: fd.value === modelData
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3; color: root.accent
                    }
                    MouseArea {
                        id: optMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { fd.value = modelData; _popup.close() }
                    }
                }
            }
        }
    }
}
