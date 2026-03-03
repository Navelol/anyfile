import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Column {
    id: adv
    spacing: 0

    // ── Exposed properties ────────────────────────────────────────────────────
    // Set by FilePanel to drive relevant codec presets
    property string targetExt: ""

    property string videoCodec:   ""
    property string audioCodec:   ""
    property string videoBitrate: ""
    property string audioBitrate: ""
    property string resolution:   ""
    property string framerate:    ""
    property string crfValue:     ""
    property bool   forceOverwrite: false

    property bool expanded: false

    // Apply a preset object (from bridge.codecPresetsFor) to all fields
    function applyPreset(p) {
        videoCodec   = p.videoCodec   || ""
        audioCodec   = p.audioCodec   || ""
        audioBitrate = p.audioBitrate || ""
        crfValue     = (p.crf !== undefined && p.crf !== "") ? String(p.crf) : ""
        // Sync text inputs explicitly (binding was broken by prior user edit)
        vcInput.text  = videoCodec
        acInput.text  = audioCodec
        abInput.text  = audioBitrate
        crfInput.text = crfValue
    }

    // ── Expand/collapse divider ───────────────────────────────────────────────
    Item {
        width: parent.width
        height: 32

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 1; color: root.border
        }
        Rectangle {
            anchors.centerIn: parent
            color: root.bg
            width: toggleRow.implicitWidth + 16
            height: 24
            Row {
                id: toggleRow; anchors.centerIn: parent; spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: adv.expanded ? "▲" : "▼"; font.pixelSize: 9; color: root.textDim }
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: "ADVANCED OPTIONS"; font.pixelSize: 9; font.bold: true
                    font.family: root.appFont; font.letterSpacing: 2; color: root.textDim }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: adv.expanded = !adv.expanded
            }
        }
    }

    // ── Collapsible body ──────────────────────────────────────────────────────
    Item {
        width: parent.width
        height: adv.expanded ? advBody.implicitHeight + 24 : 0
        clip: true
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Column {
            id: advBody
            anchors.top: parent.top; anchors.topMargin: 12
            anchors.left: parent.left; anchors.right: parent.right
            spacing: 14

            // ── Codec presets ─────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 6
                visible: presetsRepeater.count > 0

                Text {
                    text: "PRESETS  —  click to fill settings below"
                    font.pixelSize: 9; font.bold: true; font.family: root.appFont
                    font.letterSpacing: 2; color: root.textDim
                }

                ScrollView {
                    width: parent.width; height: presetFlow.implicitHeight + 4
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff; clip: true

                    Flow {
                        id: presetFlow; spacing: 6; width: parent.width

                        Repeater {
                            id: presetsRepeater
                            model: adv.targetExt !== "" ? bridge.codecPresetsFor(adv.targetExt) : []

                            Rectangle {
                                width: pCol.implicitWidth + 18
                                height: pCol.implicitHeight + 12
                                radius: 8
                                color: pMa.containsMouse ? root.surfaceHi : root.surface
                                border.color: pMa.containsMouse ? root.accent : root.border
                                border.width: 1
                                Behavior on color      { ColorAnimation { duration: 80 } }
                                Behavior on border.color { ColorAnimation { duration: 80 } }

                                Column {
                                    id: pCol; anchors.centerIn: parent; spacing: 3
                                    Text {
                                        text: modelData.name
                                        font.pixelSize: 11; font.family: root.appFont
                                        color: root.textPrim; font.bold: true
                                    }
                                    Text {
                                        text: modelData.desc
                                        font.pixelSize: 9; font.family: root.appFont
                                        color: root.textDim; width: pCol.implicitWidth
                                    }
                                }
                                MouseArea {
                                    id: pMa; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: adv.applyPreset(modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ── Fields grid ───────────────────────────────────────────────────
            GridLayout {
                width: parent.width
                columns: 4; columnSpacing: 12; rowSpacing: 8

                // helper: field label + ? tooltip + text input
                // We use explicit items for reliable two-way binding with applyPreset()

                // Video Codec
                ColumnLayout {
                    spacing: 4
                    AdvFieldLabel {
                        label: "Video Codec"
                        tip: "FFmpeg video encoder.\nCPU: libx264 (H.264), libx265 (H.265/HEVC), libaom-av1 (AV1).\nGPU (NVIDIA): h264_nvenc, hevc_nvenc.\nGPU (macOS): h264_videotoolbox.\nLeave blank for format default."
                    }
                    AdvTextInput {
                        id: vcInput; hint: "libx264, hevc_nvenc"
                        onTextChanged: adv.videoCodec = text
                    }
                }

                // Audio Codec
                ColumnLayout {
                    spacing: 4
                    AdvFieldLabel {
                        label: "Audio Codec"
                        tip: "FFmpeg audio encoder.\naac — AAC, best for MP4/MOV.\nlibopus — Opus, best for WebM/OGG.\nlibmp3lame — MP3.\nflac — lossless FLAC.\npcm_s16le — uncompressed WAV.\nLeave blank for format default."
                    }
                    AdvTextInput {
                        id: acInput; hint: "aac, libopus"
                        onTextChanged: adv.audioCodec = text
                    }
                }

                // Video Bitrate
                ColumnLayout {
                    spacing: 4
                    AdvFieldLabel {
                        label: "Video Bitrate"
                        tip: "Target video bitrate.\nUse 'k' for kbps (e.g. 800k) or 'M' for Mbps (e.g. 2M).\nLeave blank to use CRF quality-based encoding instead.\nTip: 4K ~15–40M, 1080p ~4–8M, 720p ~1.5–4M."
                    }
                    AdvTextInput {
                        id: vbInput; hint: "2M, 500k"
                        onTextChanged: adv.videoBitrate = text
                    }
                }

                // Audio Bitrate
                ColumnLayout {
                    spacing: 4
                    AdvFieldLabel {
                        label: "Audio Bitrate"
                        tip: "Target audio bitrate.\nCommon values: 96k (voice), 128k (acceptable), 192k (good), 320k (high quality).\nNot used for lossless codecs (flac, pcm_*).\nLibopus has a 510k maximum."
                    }
                    AdvTextInput {
                        id: abInput; hint: "192k, 320k"
                        onTextChanged: adv.audioBitrate = text
                    }
                }

                // Resolution
                ColumnLayout {
                    spacing: 4
                    AdvFieldLabel {
                        label: "Resolution"
                        tip: "Output video resolution as WxH.\nExamples: 3840x2160 (4K), 1920x1080 (FHD), 1280x720 (HD), 854x480 (SD).\nLeave blank to keep source resolution.\nAspect ratio is not automatically preserved — use ffmpeg -vf scale=-2:720 via codec flag if needed."
                    }
                    AdvTextInput {
                        id: resInput; hint: "1920x1080"
                        onTextChanged: adv.resolution = text
                    }
                }

                // Framerate
                ColumnLayout {
                    spacing: 4
                    AdvFieldLabel {
                        label: "Framerate"
                        tip: "Output frames per second.\nCommon values: 23.976 (film NTSC), 24 (cinema), 25 (PAL/broadcast), 29.97 / 30, 50, 59.94 / 60 (gaming/sports).\nLeave blank to keep source framerate."
                    }
                    AdvTextInput {
                        id: fpsInput; hint: "24, 30, 60"
                        onTextChanged: adv.framerate = text
                    }
                }

                // CRF
                ColumnLayout {
                    spacing: 4
                    AdvFieldLabel {
                        label: "CRF Quality"
                        tip: "Constant Rate Factor — quality-based encoding.\nH.264: 18 = visually lossless, 23 = default, 28 = smaller/reduced quality.\nH.265: ~4 lower for equivalent quality (e.g. 22 ≈ H.264 at 26).\nVP9: 0–63, lower is better (default 31).\nIgnored when Video Bitrate is set."
                    }
                    AdvTextInput {
                        id: crfInput; hint: "0–51  (lower = better)"
                        onTextChanged: adv.crfValue = text
                    }
                }

                // Force overwrite
                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "Overwrite"
                        font.pixelSize: 10; font.family: root.appFont
                        color: root.textDim; font.letterSpacing: 0.5
                    }
                    Rectangle {
                        width: 170; height: 28; radius: 7
                        color: adv.forceOverwrite ? "#3a2020" : root.surfaceHi
                        border.color: adv.forceOverwrite ? root.errorClr : root.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Row {
                            anchors.centerIn: parent; spacing: 7
                            Rectangle {
                                width: 12; height: 12; radius: 3
                                color: adv.forceOverwrite ? root.errorClr : "transparent"
                                border.color: adv.forceOverwrite ? root.errorClr : root.textDim
                                border.width: 1.5
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }
                            Text {
                                text: adv.forceOverwrite
                                      ? "on — replaces existing files"
                                      : "off — ask before replacing"
                                font.pixelSize: 10; font.family: root.appFont
                                color: adv.forceOverwrite ? root.errorClr : root.textDim
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: adv.forceOverwrite = !adv.forceOverwrite
                        }
                    }
                }
            }
        }
    }

    // ── Inline components ─────────────────────────────────────────────────────
    component AdvFieldLabel: RowLayout {
        property string label: ""
        property string tip:   ""
        spacing: 4
        Text {
            text: label
            font.pixelSize: 10; font.family: root.appFont
            color: root.textDim; font.letterSpacing: 0.5
        }
        // ? help icon with ToolTip
        Rectangle {
            width: 14; height: 14; radius: 7
            color: hMa.containsMouse ? root.border : "transparent"
            border.color: hMa.containsMouse ? root.accent : root.textDim
            border.width: 1
            Text { anchors.centerIn: parent; text: "?"; font.pixelSize: 8; color: root.textDim }
            MouseArea {
                id: hMa; anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            }
            ToolTip {
                parent: hMa; visible: hMa.containsMouse
                text: tip; delay: 200; timeout: 12000
                contentItem: Text {
                    text: parent.text; font.pixelSize: 11; font.family: root.appFont
                    color: root.textPrim; wrapMode: Text.Wrap; width: 280
                }
                background: Rectangle {
                    color: root.surfaceHi; radius: 8
                    border.color: root.accent; border.width: 1
                }
            }
        }
    }

    component AdvTextInput: Rectangle {
        property alias text: ti.text
        property string hint: ""
        signal textChanged(string t)
        width: 170; height: 28; radius: 7
        color: root.surfaceHi
        border.color: ti.activeFocus ? root.accent : root.border
        border.width: 1
        TextInput {
            id: ti; anchors.fill: parent; anchors.margins: 6
            font.pixelSize: 12; font.family: root.appFont; color: root.textPrim
            onTextChanged: parent.textChanged(text)
            Text {
                anchors.fill: parent; text: parent.parent.hint; font: parent.font
                color: root.textDim; visible: parent.text.length === 0 && !parent.activeFocus
            }
        }
    }
}
