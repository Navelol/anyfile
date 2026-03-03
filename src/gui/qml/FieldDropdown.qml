import QtQuick
import QtQuick.Controls
import QtQuick.Window

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

    width: 170; height: 28; radius: 7
    color: btnMa.containsMouse ? root.border : root.surfaceHi
    border.color: (optPop.visible || btnMa.containsMouse) ? root.accent : root.border
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
            text: optPop.visible ? "\u25b4" : "\u25be"
            font.pixelSize: 9; color: root.textDim
        }
    }

    MouseArea {
        id: btnMa; anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: optPop.visible ? optPop.close() : optPop.open()
    }

    Popup {
        id: optPop
        y: fd.height + 2   // adjusted in onAboutToShow
        width: Math.max(fd.width, 160)
        padding: 0
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        onAboutToShow: {
            var rows = fd.options.length + 1
            var contentH = rows * 26 + 8  // 4px top+bottom insets in Column
            var sceneY = fd.mapToItem(null, 0, 0).y
            y = (sceneY + fd.height + 2 + contentH > fd.Window.height)
                ? -(contentH + 2) : fd.height + 2
        }

        background: Rectangle {
            color: root.surfaceHi; radius: 7
            border.color: root.accent; border.width: 1
        }

        contentItem: Column {
            spacing: 0
            topPadding: 5; bottomPadding: 5
            leftPadding: 1; rightPadding: 1

            // "none / clear" row
            Rectangle {
                width: optPop.width - 2; height: 26
                color: clearMa.containsMouse ? root.border : "transparent"
                Behavior on color { ColorAnimation { duration: 60 } }
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
                    onClicked: { fd.value = ""; optPop.close() }
                }
            }

            Repeater {
                model: fd.options
                Rectangle {
                    width: optPop.width - 2; height: 26
                    color: optMa.containsMouse ? root.border : "transparent"
                    Behavior on color { ColorAnimation { duration: 60 } }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 8
                        text: modelData; font.pixelSize: 11; font.family: root.appFont
                        color: root.textPrim
                    }
                    // Active indicator dot
                    Rectangle {
                        visible: fd.value === modelData
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3; color: root.accent
                    }
                    MouseArea {
                        id: optMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { fd.value = modelData; optPop.close() }
                    }
                }
            }
        }
    }
}
