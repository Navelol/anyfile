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
    property bool   allowCustomValue: false
    property var    customValidator: null
    property int    customMaximumLength: 64
    property int    customInputHints: 0
    property int    hoveredRow: -2 // -2 none, -1 clear row, >=0 option row

    function setValue(v) { value = v }

    // Close when this item is hidden or destroyed
    onVisibleChanged: if (!visible) _popup.close()

    width: 170; height: 28; radius: 7
    color: btnMa.containsMouse ? root.border : root.surfaceHi
    border.color: _popup.opened ? root.accent : (btnMa.containsMouse ? root.textDim : root.border)
    border.width: 1
    Behavior on color { ColorAnimation { duration: 80 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Row {
        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6
        spacing: 0

        Text {
            visible: !fd.allowCustomValue
            width: parent.width - arrowLbl.width - 6
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: fd.value !== "" ? fd.value : fd.hint
            font.pixelSize: 12; font.family: root.appFont
            color: fd.value !== "" ? root.textPrim : root.textDim
            elide: Text.ElideRight
        }

        TextInput {
            id: customInput
            visible: fd.allowCustomValue
            width: parent.width - arrowLbl.width - 8
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: fd.value
            font.pixelSize: 12
            font.family: root.appFont
            color: root.textPrim
            inputMethodHints: fd.customInputHints
            validator: fd.customValidator
            maximumLength: fd.customMaximumLength
            onTextEdited: fd.value = text

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: fd.hint
                font.pixelSize: 12
                font.family: root.appFont
                color: root.textDim
                elide: Text.ElideRight
                visible: parent.text.length === 0 && !parent.activeFocus
            }
        }

        Text {
            id: arrowLbl
            anchors.verticalCenter: parent.verticalCenter
            text: _popup.opened ? "\u25b4" : "\u25be"
            font.pixelSize: 9; color: root.textDim
            width: 14
            horizontalAlignment: Text.AlignHCenter
        }
    }

    MouseArea {
        id: btnMa; anchors.fill: parent
        visible: !fd.allowCustomValue
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: _popup.opened ? _popup.close() : _popup.open()
    }

    MouseArea {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 22
        visible: fd.allowCustomValue
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
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
        onOpenedChanged: {
            if (!opened) {
                fd.hoveredRow = -2
            }
        }

        background: Rectangle {
            radius: 7
            color: root.surfaceHi
            border.color: root.border
            border.width: 1
        }

        // No background dim / overlay from Controls
        dim: false

        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 100; easing.type: Easing.OutCubic } }
        exit:  Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80;  easing.type: Easing.InCubic  } }

        Item {
            id: contentCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.topMargin: 5
            implicitHeight: rowsCol.implicitHeight

            HoverHandler {
                onHoveredChanged: if (!hovered) fd.hoveredRow = -2
            }

            Rectangle {
                visible: fd.hoveredRow >= -1
                anchors.left: parent.left
                anchors.right: parent.right
                height: 26
                radius: 4
                y: fd.hoveredRow < 0 ? 0 : (fd.hoveredRow + 1) * 26
                color: Qt.lighter(root.surfaceHi, 1.12)
                border.color: Qt.lighter(root.border, 1.22)
                border.width: 1
                z: 0
                Behavior on y { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 70 } }
            }

            Column {
                id: rowsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 0
                z: 1

                // "none / clear" row
                Rectangle {
                    width: parent.width; height: 26; radius: 4
                    color: "transparent"
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
                        onEntered: fd.hoveredRow = -1
                        onClicked: { fd.value = ""; _popup.close() }
                    }
                }

                Repeater {
                    model: fd.options
                    Rectangle {
                        width: parent.width; height: 26; radius: 4
                        color: "transparent"
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
                            onEntered: fd.hoveredRow = index
                            onClicked: { fd.value = modelData; _popup.close() }
                        }
                    }
                }
            }
        }
    }
}
