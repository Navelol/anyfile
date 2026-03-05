import QtQuick

// Thin custom scrollbar that mirrors the preset-area style.
//
// Usage (horizontal):
//   AppScrollBar { target: someFlickableOrItem; orientation: Qt.Horizontal }
//
// Usage (vertical):
//   AppScrollBar { target: someFlickableOrItem; orientation: Qt.Vertical }
//
// For Flickable/ListView targets, bind flickable: myListView
// For manual-position tracks (like the preset drag track), bind:
//   contentSize / visibleSize / position (read) and onMoved (write-back)

Item {
    id: sb

    // ── Required: one of these two APIs ──────────────────────────────────────
    // Option A — Flickable / ListView (most cases)
    property Flickable flickable: null

    // Option B — manual (preset drag track)
    property real contentSize: flickable ? (orientation === Qt.Horizontal
                                            ? flickable.contentWidth
                                            : flickable.contentHeight) : 0
    property real visibleSize: flickable ? (orientation === Qt.Horizontal
                                            ? flickable.width
                                            : flickable.height) : 0
    property real position:    flickable ? (orientation === Qt.Horizontal
                                            ? flickable.contentX
                                            : flickable.contentY) : 0
    signal moved(real newPosition)

    // ── Config ────────────────────────────────────────────────────────────────
    property int orientation: Qt.Vertical
    property int thickness:   3

    // ── Derived ───────────────────────────────────────────────────────────────
    readonly property bool horizontal: orientation === Qt.Horizontal
    readonly property bool hasOverflow: contentSize > visibleSize + 1
    readonly property real scrollRange: contentSize - visibleSize  // total scrollable distance
    readonly property real trackLen:    horizontal ? width : height

    // thumb length proportional to visible/content
    readonly property real thumbLen: hasOverflow
        ? Math.max(24, trackLen * (visibleSize / contentSize))
        : trackLen

    // thumb position along track
    readonly property real thumbPos: hasOverflow && scrollRange > 0
        ? (position / scrollRange) * (trackLen - thumbLen)
        : 0

    visible: hasOverflow
    width:  horizontal ? (parent ? parent.width  : 0) : thickness
    height: horizontal ? thickness : (parent ? parent.height : 0)

    // ── Track ─────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: sb.thickness / 2
        color: root.border
    }

    // ── Thumb ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: thumb
        radius: sb.thickness / 2
        color: ma.containsMouse || ma.pressed ? root.accent : root.textDim
        Behavior on color { ColorAnimation { duration: 80 } }

        x: sb.horizontal ? sb.thumbPos : 0
        y: sb.horizontal ? 0 : sb.thumbPos
        width:  sb.horizontal ? sb.thumbLen : sb.thickness
        height: sb.horizontal ? sb.thickness : sb.thumbLen

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: sb.horizontal ? Qt.SizeHorCursor : Qt.SizeVerCursor
            property real _startMouse: 0
            property real _startPos:   0
            onPressed: function(mouse) {
                // Map to sb (track) coordinates so origin doesn't drift as thumb moves
                var pt = mapToItem(sb, mouse.x, mouse.y)
                _startMouse = sb.horizontal ? pt.x : pt.y
                _startPos   = sb.position
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var pt       = mapToItem(sb, mouse.x, mouse.y)
                var curMouse = sb.horizontal ? pt.x : pt.y
                var ratio    = sb.scrollRange / (sb.trackLen - sb.thumbLen)
                var newPos   = Math.max(0, Math.min(sb.scrollRange, _startPos + (curMouse - _startMouse) * ratio))
                if (sb.flickable) {
                    if (sb.horizontal) sb.flickable.contentX = newPos
                    else               sb.flickable.contentY = newPos
                } else {
                    sb.moved(newPos)
                }
            }
        }
    }

    // ── Wheel handler (when no flickable — flickables handle wheel natively) ──
    WheelHandler {
        enabled: !sb.flickable
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            var delta = sb.horizontal ? -event.angleDelta.x || -event.angleDelta.y
                                      :  event.angleDelta.y
            var newPos = Math.max(0, Math.min(sb.scrollRange, sb.position - delta * 0.5))
            sb.moved(newPos)
        }
    }
}
