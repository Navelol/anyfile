import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Column {
    id: adv
    spacing: 0
    property int  animMs: 170
    property bool _fadeArmed: false

    // ── Exposed properties ────────────────────────────────────────────────────
    property string targetExt: ""

    property string videoCodec:    ""
    property string audioCodec:    ""
    property string videoBitrate:  ""    // VBR target bitrate
    property string videoMaxRate:  ""    // VBR max bitrate
    property string audioBitrate:  ""
    property string resolution:    ""
    property string framerate:     ""
    property string crfValue:      ""
    property string rateMode:      "crf"  // "crf" | "vbr1" | "vbr2"
    property bool   forceOverwrite: false

    property bool expanded: false
    property var  presentCategories: []

    // Drive field visibility from targetExt directly — much simpler and correct
    property bool showVideoFields: ["mp4","mkv","webm","mov","avi","ts","m4v"].indexOf(targetExt) >= 0
    property bool showAudioFields: ["mp4","mkv","webm","mov","avi","ts","m4v",
                                    "mp3","flac","wav","ogg","opus","aac","m4a"].indexOf(targetExt) >= 0
    property bool isGifTarget: targetExt === "gif"

    property var videoCodecOptions: {
        var ext = adv.targetExt
        if (ext === "webm") return ["libvpx-vp9","libvpx","libaom-av1"]
        if (ext === "mov")  return ["libx264","libx265","prores_ks","h264_videotoolbox","copy"]
        if (ext === "avi")  return ["mpeg4","libx264","libxvid","copy"]
        if (ext === "mkv")  return ["libx264","libx265","libvpx-vp9","libaom-av1","h264_nvenc","hevc_nvenc","copy"]
        return ["libx264","libx265","libaom-av1","h264_nvenc","hevc_nvenc","h264_videotoolbox","copy"]
    }
    property var audioCodecOptions: {
        var ext = adv.targetExt
        if (ext === "webm" || ext === "opus") return ["libopus","libvorbis"]
        if (ext === "ogg")  return ["libvorbis","libopus"]
        if (ext === "mp3")  return ["libmp3lame"]
        if (ext === "flac") return ["flac"]
        if (ext === "wav")  return ["pcm_s16le","pcm_s24le","pcm_f32le"]
        if (ext === "aac" || ext === "m4a") return ["aac","libfdk_aac"]
        if (ext === "mov")  return ["aac","pcm_s16le","copy"]
        return ["aac","libopus","libmp3lame","flac","libvorbis","pcm_s16le","pcm_s24le","copy"]
    }

    // VBR only makes sense for video containers
    property bool supportsVBR: {
        var ext = adv.targetExt
        return ext === "mp4" || ext === "mkv" || ext === "mov" || ext === "webm"
            || ext === "avi" || ext === "ts"  || ext === "m4v" || ext === ""
    }

    onTargetExtChanged: {
        if (!adv._fadeArmed) { adv._fadeArmed = true; return }
        if (adv.isGifTarget) {
            videoCodec = ""; audioCodec = ""; audioBitrate = ""
            videoBitrate = ""; videoMaxRate = ""; crfValue = ""; rateMode = "crf"
            vcInput.setValue("")
            acInput.setValue("")
            abInput.setValue("")
            vbTarget.setValue("")
            vbMax.setValue("")
            crfInput.setValue("")
        }
        advBody.opacity = 0.0
        advBodyFadeIn.restart()
    }
    onPresentCategoriesChanged: {
        if (!adv._fadeArmed) return
        advBody.opacity = 0.0
        advBodyFadeIn.restart()
    }

    // Apply a preset — handles both CRF and VBR presets
    function applyPreset(p) {
        videoCodec   = p.videoCodec   || ""
        audioCodec   = p.audioCodec   || ""
        audioBitrate = p.audioBitrate || ""
        vcInput.setValue(videoCodec)
        acInput.setValue(audioCodec)
        abInput.setValue(audioBitrate)

        if (p.rateMode === "vbr1" || p.rateMode === "vbr2") {
            rateMode     = p.rateMode
            videoBitrate = p.videoBitrate || ""
            videoMaxRate = p.videoMaxRate || ""
            crfValue     = ""
            vbTarget.setValue(videoBitrate)
            vbMax.setValue(videoMaxRate)
            crfInput.setValue("")
        } else {
            rateMode     = "crf"
            crfValue     = (p.crf !== undefined && p.crf !== "") ? String(p.crf) : ""
            videoBitrate = ""; videoMaxRate = ""
            crfInput.setValue(crfValue)
            vbTarget.setValue(""); vbMax.setValue("")
        }
    }

    // ── Expand/collapse divider ───────────────────────────────────────────────
    Item {
        width: parent.width; height: 32
        Rectangle { anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 1; color: root.border }
        Rectangle {
            anchors.centerIn: parent; color: root.bg
            width: toggleRow.implicitWidth + 16; height: 24
            Row { id: toggleRow; anchors.centerIn: parent; spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: adv.expanded ? "▼" : "▲"; font.pixelSize: 9; color: root.textDim }
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: "GLOBAL ADVANCED OPTIONS"; font.pixelSize: 9; font.bold: true
                    font.family: root.appFont; font.letterSpacing: 2; color: root.textDim }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: adv.expanded = !adv.expanded }
        }
    }

    // ── Collapsible body ──────────────────────────────────────────────────────
    Item {
        width: parent.width
        height: adv.expanded ? advBody.implicitHeight + 12 : 0
        clip: true
        Behavior on height { NumberAnimation { duration: animMs; easing.type: Easing.InOutCubic } }

        Column {
            id: advBody
            anchors.top: parent.top; anchors.topMargin: 8
            anchors.left: parent.left; anchors.right: parent.right
            spacing: 8
            opacity: 1.0

            NumberAnimation {
                id: advBodyFadeIn
                target: advBody
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: adv.animMs
                easing.type: Easing.InOutCubic
            }

            // ── Preset cards — drag-scrollable ────────────────────────────────
            Column {
                width: parent.width; spacing: 4
                visible: presetsRepeater.count > 0

                Text {
                    text: "PRESETS  —  click to apply"
                    font.pixelSize: 9; font.bold: true; font.family: root.appFont
                    font.letterSpacing: 2; color: root.textDim
                }

                Item {
                    width: parent.width; height: 54; clip: true

                    Item {
                        id: presetTrack
                        height: parent.height
                        width: Math.max(presetClipArea.width, presetsRow.implicitWidth + 4)
                        property real minX: presetClipArea.width - width
                        property real maxX: 0.0
                        x: 0

                        property alias clipAreaRef: presetClipArea

                        Row {
                            id: presetsRow; x: 0; y: 0; height: parent.height; spacing: 6

                            Repeater {
                                id: presetsRepeater
                                model: adv.targetExt !== "" ? bridge.codecPresetsFor(adv.targetExt) : []

                                Rectangle {
                                    width: 128; height: 50; radius: 8; clip: true
                                    color: cardMa.containsMouse && !dragH.active
                                           ? root.surfaceHi : root.surface
                                    border.width: 1
                                    border.color: cardMa.containsMouse && !dragH.active
                                                  ? root.accent : root.border
                                    Behavior on color        { ColorAnimation { duration: 80 } }
                                    Behavior on border.color { ColorAnimation { duration: 80 } }

                                    // VBR badge
                                    Rectangle {
                                        visible: modelData.rateMode === "vbr1" || modelData.rateMode === "vbr2"
                                        anchors.top: parent.top; anchors.right: parent.right
                                        anchors.topMargin: 5; anchors.rightMargin: 5
                                        width: badgeLbl.implicitWidth + 8; height: 14; radius: 3
                                        color: "#0e1e2e"; border.color: "#4488bb"; border.width: 1
                                        Text { id: badgeLbl; anchors.centerIn: parent
                                            text: modelData.rateMode === "vbr2" ? "VBR 2-pass" : "VBR"
                                            font.pixelSize: 8; font.family: root.appFont
                                            font.bold: true; color: "#88ccee" }
                                    }

                                    Column {
                                        anchors { left: parent.left; right: parent.right
                                                  top: parent.top; margins: 8 }
                                        spacing: 2
                                        Text { text: modelData.name
                                            font.pixelSize: 10; font.family: root.appFont
                                            color: root.textPrim; font.bold: true
                                            width: parent.width - 2; wrapMode: Text.WordWrap }
                                        Text { text: modelData.desc
                                            font.pixelSize: 8; font.family: root.appFont
                                            color: root.textDim; width: parent.width - 2
                                            wrapMode: Text.WordWrap }
                                    }

                                    MouseArea { id: cardMa; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (!dragH.active) adv.applyPreset(modelData) } }
                                }
                            }
                        }

                        DragHandler {
                            id: dragH
                            xAxis.enabled: true; yAxis.enabled: false
                            xAxis.minimum: presetTrack.minX
                            xAxis.maximum: presetTrack.maxX
                        }
                    }

                    // Fade edges hint at more content
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top
                        anchors.bottom: parent.bottom; width: 24
                        visible: presetTrack.x < -2
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.bg }
                            GradientStop { position: 1.0; color: "transparent" } }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.top: parent.top
                        anchors.bottom: parent.bottom; width: 24
                        visible: presetTrack.x > presetTrack.minX + 2
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: root.bg } }
                    }

                    // Wheel-to-scroll
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(event) {
                            var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                            presetTrack.x = Math.max(presetTrack.minX, Math.min(0, presetTrack.x + delta * 0.5))
                        }
                    }

                    // Capture ID for width reference
                    Item { id: presetClipArea; anchors.fill: parent }
                }

                // Scrollbar
                AppScrollBar {
                    width: parent.width; height: 4
                    orientation: Qt.Horizontal
                    contentSize: presetTrack.width
                    visibleSize: presetClipArea.width
                    position: -presetTrack.x
                    onMoved: function(p) { presetTrack.x = -p }
                }
            }

            // ── Rate mode selector ────────────────────────────────────────────
            Column {
                width: parent.width; spacing: 3
                visible: adv.showVideoFields && adv.supportsVBR && !adv.isGifTarget

                Text { text: "RATE CONTROL"
                    font.pixelSize: 9; font.bold: true; font.family: root.appFont
                    font.letterSpacing: 2; color: root.textDim }

                Row {
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "crf",  label: "CRF",        tip: "Quality-based — best for local files.\nLower number = higher quality.\nFile size varies based on content." },
                            { id: "vbr1", label: "VBR 1-pass", tip: "Variable bitrate, single pass.\nFast encode, targets a bitrate.\nGood for streaming or delivery." },
                            { id: "vbr2", label: "VBR 2-pass", tip: "Variable bitrate, two passes.\nBest bitrate accuracy.\nTwice as slow — worth it for final exports." },
                        ]
                        Rectangle {
                            property bool active: adv.rateMode === modelData.id
                            width: rmLbl.implicitWidth + 18; height: 24; radius: 7
                            color: active ? "#1a2a1a" : (rmMa.containsMouse ? root.surfaceHi : root.surface)
                            border.color: active ? root.accent : root.border
                            border.width: active ? 1.5 : 1
                            Behavior on color        { ColorAnimation { duration: 80 } }
                            Behavior on border.color { ColorAnimation { duration: 80 } }
                            Text { id: rmLbl; anchors.centerIn: parent; text: modelData.label
                                font.pixelSize: 11; font.family: root.appFont; font.bold: active
                                color: active ? root.accent : root.textDim }
                            MouseArea { id: rmMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                ToolTip.visible: containsMouse; ToolTip.delay: 300
                                ToolTip.text: modelData.tip
                                onClicked: {
                                    adv.rateMode = modelData.id
                                    if (modelData.id === "crf") {
                                        adv.videoBitrate = ""; adv.videoMaxRate = ""
                                        vbTarget.setValue(""); vbMax.setValue("")
                                    } else {
                                        adv.crfValue = ""; crfInput.setValue("")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Fields grid ───────────────────────────────────────────────────
            GridLayout {
                width: parent.width
                columns: 4; columnSpacing: 10; rowSpacing: 4

                // Video Codec
                ColumnLayout {
                    spacing: 3
                    visible: adv.showVideoFields && !adv.isGifTarget
                    Layout.alignment: Qt.AlignTop
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: adv.animMs; easing.type: Easing.InOutCubic } }
                    AdvFieldLabel { label: "Video Codec"
                        tip: "FFmpeg video encoder.\nCPU: libx264 (H.264), libx265 (H.265), libaom-av1 (AV1).\nGPU NVIDIA: h264_nvenc, hevc_nvenc.\nGPU Apple: h264_videotoolbox.\nLeave blank for format default." }
                    FieldDropdown { id: vcInput; hint: "libx264, hevc_nvenc"
                        options: adv.videoCodecOptions
                        onValueChanged: adv.videoCodec = value }
                }

                // Audio Codec
                ColumnLayout {
                    spacing: 3
                    visible: adv.showAudioFields && !adv.isGifTarget
                    Layout.alignment: Qt.AlignTop
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: adv.animMs; easing.type: Easing.InOutCubic } }
                    AdvFieldLabel { label: "Audio Codec"
                        tip: "FFmpeg audio encoder.\naac — best for MP4/MOV.\nlibopus — best for WebM/OGG.\nlibmp3lame — MP3.\nflac — lossless.\npcm_s16le — uncompressed WAV.\nLeave blank for format default." }
                    FieldDropdown { id: acInput; hint: "aac, libopus"
                        options: adv.audioCodecOptions
                        onValueChanged: adv.audioCodec = value }
                }

                // Rate primary (row 1, col 3) — strict grid cell
                ColumnLayout {
                    spacing: 3
                    visible: adv.showVideoFields && !adv.isGifTarget
                    Layout.alignment: Qt.AlignTop
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: adv.animMs; easing.type: Easing.InOutCubic } }

                    AdvFieldLabel {
                        label: adv.rateMode === "crf" ? "CRF Quality" : "Target Bitrate"
                        tip: adv.rateMode === "crf"
                             ? "Constant Rate Factor.\nH.264: 18 = near-lossless, 23 = default, 28 = smaller.\nH.265: ~4 lower than H.264 for same quality (28 ≈ H.264 23).\nVP9: 0–63, default 31.\nAV1: 0–63, ~30 is balanced."
                             : "VBR target video bitrate.\nEncoder averages near this value.\n4K → 15–40M, 1080p → 4–8M, 720p → 1.5–4M.\nUse 'k' for kbps or 'M' for Mbps."
                    }

                    Item {
                        width: 170; height: 28
                        FieldDropdown {
                            id: crfInput
                            anchors.fill: parent
                            hint: "23 (H.264 default)"
                            options: ["16","17","18","19","20","21","22","23","24","26","28","30","31","35","40"]
                            enabled: adv.rateMode === "crf"
                            opacity: adv.rateMode === "crf" ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: adv.animMs + 10; easing.type: Easing.InOutCubic } }
                            onValueChanged: adv.crfValue = value
                        }
                        FieldDropdown {
                            id: vbTarget
                            anchors.fill: parent
                            hint: "4M, 8M"
                            options: ["500k","1M","2M","3M","4M","6M","8M","12M","15M","20M","30M","40M"]
                            enabled: adv.rateMode !== "crf"
                            opacity: adv.rateMode !== "crf" ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: adv.animMs + 10; easing.type: Easing.InOutCubic } }
                            onValueChanged: adv.videoBitrate = value
                        }
                    }
                }

                // Audio Bitrate
                ColumnLayout {
                    spacing: 3
                    visible: adv.showAudioFields && !adv.isGifTarget
                    Layout.alignment: Qt.AlignTop
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: adv.animMs; easing.type: Easing.InOutCubic } }
                    AdvFieldLabel { label: "Audio Bitrate"
                        tip: "Target audio bitrate.\n96k — voice.\n128k — acceptable.\n192k — good.\n320k — high quality.\nNot used for lossless (flac, pcm_*)." }
                    FieldDropdown { id: abInput; hint: "192k, 320k"
                        options: ["64k","96k","128k","192k","256k","320k"]
                        onValueChanged: adv.audioBitrate = value }
                }

                // Resolution
                ColumnLayout {
                    spacing: 3
                    visible: adv.showVideoFields || adv.isGifTarget
                    Layout.alignment: Qt.AlignTop
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: adv.animMs; easing.type: Easing.InOutCubic } }
                    AdvFieldLabel { label: "Resolution"
                        tip: "Output resolution as WxH.\n3840x2160 (4K), 1920x1080, 1280x720, 854x480.\nLeave blank to keep source resolution." }
                    AdvTextInput { id: resInput; hint: "1920x1080"
                        onTextChanged: adv.resolution = text }
                }

                // Framerate
                ColumnLayout {
                    spacing: 3
                    visible: adv.showVideoFields || adv.isGifTarget
                    Layout.alignment: Qt.AlignTop
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: adv.animMs; easing.type: Easing.InOutCubic } }
                    AdvFieldLabel { label: "Framerate"
                        tip: "Output frames per second.\n24 (cinema), 25 (PAL), 30, 60 (gaming/sports).\nLeave blank to keep source framerate." }
                    AdvTextInput { id: fpsInput; hint: "24, 30, 60"
                        onTextChanged: adv.framerate = text }
                }

                // Rate secondary (row 2, col 3) — keeps grid stable
                ColumnLayout {
                    spacing: 3
                    visible: adv.showVideoFields && !adv.isGifTarget
                    Layout.alignment: Qt.AlignTop
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: adv.animMs; easing.type: Easing.InOutCubic } }

                    AdvFieldLabel {
                        label: "Max Bitrate"
                        tip: "VBR maximum bitrate cap.\nPrevents spikes in complex scenes.\nTypically 1.5–2× your target bitrate.\nLeave blank for no cap."
                        opacity: adv.rateMode !== "crf" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: adv.animMs + 10; easing.type: Easing.InOutCubic } }
                    }
                    FieldDropdown {
                        id: vbMax
                        hint: "leave blank or 2× target"
                        options: ["","1M","2M","4M","6M","8M","12M","16M","20M","30M","50M","60M"]
                        enabled: adv.rateMode !== "crf"
                        opacity: adv.rateMode !== "crf" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: adv.animMs + 10; easing.type: Easing.InOutCubic } }
                        onValueChanged: adv.videoMaxRate = value
                    }
                }

                ColumnLayout {
                    spacing: 3
                    Layout.alignment: Qt.AlignTop
                    Text { text: "Overwrite"; font.pixelSize: 10; font.family: root.appFont
                        color: root.textDim; font.letterSpacing: 0.5 }
                    Rectangle { width: 170; height: 28; radius: 7
                        color: adv.forceOverwrite ? "#3a2020" : root.surfaceHi
                        border.color: adv.forceOverwrite ? root.errorClr : root.border; border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Row { anchors.centerIn: parent; spacing: 7
                            Rectangle { width: 12; height: 12; radius: 3
                                color: adv.forceOverwrite ? root.errorClr : "transparent"
                                border.color: adv.forceOverwrite ? root.errorClr : root.textDim; border.width: 1.5
                                Behavior on color { ColorAnimation { duration: 80 } } }
                            Text { text: adv.forceOverwrite ? "on — replaces existing files"
                                                            : "off — ask before replacing"
                                font.pixelSize: 10; font.family: root.appFont
                                color: adv.forceOverwrite ? root.errorClr : root.textDim } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: adv.forceOverwrite = !adv.forceOverwrite } }
                }
            }
        }
    }

    // ── Inline components ─────────────────────────────────────────────────────
    component AdvFieldLabel: RowLayout {
        property string label: ""
        property string tip:   ""
        spacing: 4
        Text { text: label; font.pixelSize: 10; font.family: root.appFont
            color: root.textDim; font.letterSpacing: 0.5 }
        Rectangle { width: 14; height: 14; radius: 7
            color: hMa.containsMouse ? root.border : "transparent"
            border.color: hMa.containsMouse ? root.accent : root.textDim; border.width: 1
            Text { anchors.centerIn: parent; text: "?"; font.pixelSize: 8; color: root.textDim }
            MouseArea { id: hMa; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                ToolTip.visible: containsMouse; ToolTip.delay: 200
                ToolTip.timeout: 12000; ToolTip.text: tip } }
    }

    component AdvTextInput: Rectangle {
        property alias text: ti.text
        property string hint: ""
        width: 170; height: 28; radius: 7; color: root.surfaceHi
        border.color: ti.activeFocus ? root.accent : root.border; border.width: 1
        TextInput { id: ti; anchors.fill: parent; anchors.margins: 6
            font.pixelSize: 12; font.family: root.appFont; color: root.textPrim
            Text { anchors.fill: parent; text: parent.parent.hint; font: parent.font
                color: root.textDim; visible: parent.text.length === 0 && !parent.activeFocus } }
    }
}
