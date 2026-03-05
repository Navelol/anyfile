import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: panel

    // mode: 0 = files/batch, 1 = folder
    property int mode: 0

    // -- Batch model -----------------------------------------------------------
    // Each row: { filePath, enabled, sourceExt, targetExt,
    //             outputName, ovVideoCodec, ovAudioCodec, ovRateMode, ovVideoBitrate, ovVideoMaxRate, ovAudioBitrate, ovCrf,
    //             ovResolution, ovFramerate }
    ListModel { id: batchModel }
    property string overrideExt: ""   // if set, all enabled rows use this ext

    // Categories present in current batch/folder (drives Global Advanced Options visibility)
    // In file mode: computed from batch model. In folder mode: set once by scan worker.
    property var presentCategories: {
        if (mode === 0) {
            var cats = {}
            for (var i = 0; i < batchModel.count; i++)
                cats[bridge.categoryFor(batchModel.get(i).sourceExt)] = true
            return Object.keys(cats)
        }
        return panel._folderCategories
    }
    property var _folderCategories: []

    // -- Folder mode state -----------------------------------------------------
    property string folderPath:    ""
    property var    folderFiles:   []
    property string folderOutDir:  ""
    property bool   folderSameDir: true
    property bool   folderRecurse: true

    // Folder format rules: [{fromExt, toExt}] + a default catch-all
    ListModel { id: formatRulesModel }
    property string folderDefaultExt: ""
    onFolderDefaultExtChanged: recomputeFolderStats()

    // -- Results model (shared batch + folder) ---------------------------------
    ListModel { id: batchResults }

    Connections {
        target: bridge
        function onBatchFileCompleted(done, total, filename, success, detail) {
            batchResults.append({ filename: filename, success: success, detail: detail })
            if (batchList.count > 0) batchList.positionViewAtEnd()
        }
        function onFolderScanComplete(files, categories) {
            panel.folderFiles          = files
            panel._folderCategories    = categories
            panel.folderDefaultExt     = ""
            formatRulesModel.clear()
            panel.recomputeFolderStats()
            if (files.length >= 100000) scanLimitDialog.open()
        }
    }

    // Cached folder stats (computed once, updated when rules change)
    property int  _folderConvertCount: 0
    property bool _folderCanConvert:   false

    function recomputeFolderStats() {
        if (panel.mode !== 1 || panel.folderFiles.length === 0) {
            panel._folderConvertCount = 0
            panel._folderCanConvert   = false
            return
        }
        var rules = []
        for (var i = 0; i < formatRulesModel.count; i++)
            rules.push(formatRulesModel.get(i))
        var stats = bridge.computeFolderStats(panel.folderFiles, rules, panel.folderDefaultExt)
        panel._folderConvertCount = stats.convertCount
        panel._folderCanConvert   = stats.canConvert
    }

    // -- Helpers ---------------------------------------------------------------
    function addFile(path) {
        var ext = bridge.detectFormat(path)
        if (ext === "") return
        for (var i = 0; i < batchModel.count; i++)
            if (batchModel.get(i).filePath === path) return
        var fmts = bridge.formatsFor(path)
        var tgt  = fmts.length > 0 ? fmts[0] : ""
        batchModel.append({ filePath: path, enabled: true, sourceExt: ext, targetExt: tgt,
                            outputName: "", ovVideoCodec: "", ovAudioCodec: "",
                            ovVideoBitrate: "", ovVideoMaxRate: "", ovAudioBitrate: "", ovCrf: -1,
                            ovRateMode: "crf", ovResolution: "", ovFramerate: "" })
        // Reset global override if this file can't convert to it
        if (panel.overrideExt !== "" && fmts.indexOf(panel.overrideExt) < 0)
            panel.overrideExt = ""
    }

    function hasOverrides(index) {
        var item = batchModel.get(index)
        if (!item) return false
        return item.outputName !== "" || item.ovVideoCodec !== "" ||
               item.ovAudioCodec !== "" || item.ovVideoBitrate !== "" ||
               item.ovVideoMaxRate !== "" || item.ovAudioBitrate !== "" ||
               item.ovCrf >= 0 || item.ovRateMode === "vbr1" || item.ovRateMode === "vbr2"
    }

    function effectiveTarget(index) {
        if (overrideExt !== "") return overrideExt
        return batchModel.get(index).targetExt
    }

    function enabledCount() {
        var n = 0
        for (var i = 0; i < batchModel.count; i++)
            if (batchModel.get(i).enabled && effectiveTarget(i) !== "") n++
        return n
    }

    function buildInputsAndTargets() {
        var paths = [], exts = []
        for (var i = 0; i < batchModel.count; i++) {
            var item = batchModel.get(i)
            if (!item.enabled) continue
            var tgt = effectiveTarget(i)
            if (tgt === "") continue
            paths.push(item.filePath)
            exts.push(tgt)
        }
        return { paths: paths, exts: exts }
    }

    // Build detailed job specs for convertBatchDetailed
    function buildFilesJobSpecs() {
        var specs = []
        for (var i = 0; i < batchModel.count; i++) {
            var item = batchModel.get(i)
            if (!item.enabled) continue
            var tgt = effectiveTarget(i)
            if (tgt === "") continue
            var spec = { path: item.filePath, ext: tgt }
            if (item.outputName !== "")      spec.outputName    = item.outputName
            if (item.ovResolution !== "")    spec.resolution    = item.ovResolution
            if (item.ovFramerate !== "")     spec.framerate     = item.ovFramerate
            if (item.ovVideoCodec !== "")    spec.videoCodec    = item.ovVideoCodec
            if (item.ovAudioCodec !== "")    spec.audioCodec    = item.ovAudioCodec
            if (item.ovAudioBitrate !== "")  spec.audioBitrate  = item.ovAudioBitrate
            if (item.ovRateMode === "vbr1" || item.ovRateMode === "vbr2") {
                spec.rateMode = item.ovRateMode
                if (item.ovVideoBitrate !== "") spec.videoBitrate = item.ovVideoBitrate
                if (item.ovVideoMaxRate !== "") spec.videoMaxRate = item.ovVideoMaxRate
            } else if (item.ovCrf >= 0) {
                spec.crf = item.ovCrf
            }
            specs.push(spec)
        }
        return specs
    }

    // Resolve target ext for a folder file using rules then default,
    // but only return it if the file can actually be converted to that ext.
    function resolveTargetForFolder(filePath) {
        var src = bridge.cachedDetectFormat(filePath)
        var tgt = ""
        for (var i = 0; i < formatRulesModel.count; i++) {
            if (formatRulesModel.get(i).fromExt === src) {
                tgt = formatRulesModel.get(i).toExt
                break
            }
        }
        if (tgt === "") tgt = panel.folderDefaultExt
        if (tgt === "") return ""
        var fmts = bridge.cachedFormatsFor(filePath)
        if (fmts.indexOf(tgt) < 0) return ""
        return tgt
    }

    // Build folder job specs (each file gets a resolved target + encoding overrides)
    function buildFolderJobSpecs() {
        var specs = []
        for (var i = 0; i < folderFiles.length; i++) {
            var fp  = folderFiles[i]
            var src = bridge.cachedDetectFormat(fp)
            var tgt = ""
            var ruleIdx = -1
            for (var r = 0; r < formatRulesModel.count; r++) {
                if (formatRulesModel.get(r).fromExt === src) { tgt = formatRulesModel.get(r).toExt; ruleIdx = r; break }
            }
            if (tgt === "") tgt = folderDefaultExt
            if (tgt === "") continue
            var fmts = bridge.cachedFormatsFor(fp)
            if (fmts.indexOf(tgt) < 0) continue
            var spec = { path: fp, ext: tgt }
            if (ruleIdx >= 0) {
                var rule = formatRulesModel.get(ruleIdx)
                if (rule.ovVideoCodec   && rule.ovVideoCodec   !== "") spec.videoCodec   = rule.ovVideoCodec
                if (rule.ovAudioCodec   && rule.ovAudioCodec   !== "") spec.audioCodec   = rule.ovAudioCodec
                if (rule.ovAudioBitrate && rule.ovAudioBitrate !== "") spec.audioBitrate = rule.ovAudioBitrate
                if (rule.ovResolution   && rule.ovResolution   !== "") spec.resolution   = rule.ovResolution
                if (rule.ovFramerate    && rule.ovFramerate    !== "") spec.framerate     = rule.ovFramerate
                if (rule.ovRateMode === "vbr1" || rule.ovRateMode === "vbr2") {
                    spec.rateMode = rule.ovRateMode
                    if (rule.ovVideoBitrate && rule.ovVideoBitrate !== "") spec.videoBitrate = rule.ovVideoBitrate
                    if (rule.ovVideoMaxRate && rule.ovVideoMaxRate !== "") spec.videoMaxRate = rule.ovVideoMaxRate
                } else if (rule.ovCrf >= 0) {
                    spec.crf = rule.ovCrf
                }
            }
            specs.push(spec)
        }
        return specs
    }

    // Unique source extensions present in the folder
    function sourcesInFolder() {
        var seen = {}, result = []
        for (var i = 0; i < folderFiles.length; i++) {
            var ext = bridge.cachedDetectFormat(folderFiles[i])
            if (ext !== "" && !seen[ext]) { seen[ext] = true; result.push(ext) }
        }
        return result.sort()
    }

    // Primary target ext (first non-empty target in files, or folder resolved)
    function primaryTargetExt() {
        if (mode === 0) {
            for (var i = 0; i < batchModel.count; i++) {
                var t = effectiveTarget(i)
                if (t !== "") return t
            }
        } else {
            for (var j = 0; j < folderFiles.length; j++) {
                var t2 = resolveTargetForFolder(folderFiles[j])
                if (t2 !== "") return t2
            }
        }
        return ""
    }

    function unionFormats() {
        if (batchModel.count === 0) return []
        // Intersection: only formats every file can convert to
        var sets = []
        for (var i = 0; i < batchModel.count; i++) {
            var fmts = bridge.formatsFor(batchModel.get(i).filePath)
            var s = {}
            for (var j = 0; j < fmts.length; j++) s[fmts[j]] = true
            sets.push(s)
        }
        var first = sets[0]
        var result = []
        for (var ext in first) {
            var inAll = true
            for (var k = 1; k < sets.length; k++)
                if (!sets[k][ext]) { inAll = false; break }
            if (inAll) result.push(ext)
        }
        return result.sort()
    }

    function folderFormats() {
        var seen = {}, result = []
        for (var i = 0; i < folderFiles.length; i++) {
            var fmts = bridge.cachedFormatsFor(folderFiles[i])
            for (var j = 0; j < fmts.length; j++)
                if (!seen[fmts[j]]) { seen[fmts[j]] = true; result.push(fmts[j]) }
        }
        return result.sort()
    }

    function buildOptions() {
        var opts = {}
        if (advPanel.videoCodec.length   > 0) opts["videoCodec"]   = advPanel.videoCodec
        if (advPanel.audioCodec.length   > 0) opts["audioCodec"]   = advPanel.audioCodec
        if (advPanel.videoBitrate.length > 0) opts["videoBitrate"] = advPanel.videoBitrate
        if (advPanel.audioBitrate.length > 0) opts["audioBitrate"] = advPanel.audioBitrate
        if (advPanel.resolution.length   > 0) opts["resolution"]   = advPanel.resolution
        if (advPanel.framerate.length    > 0) opts["framerate"]    = advPanel.framerate
        if (advPanel.crfValue.length     > 0) opts["crf"]          = parseInt(advPanel.crfValue)
        if (advPanel.forceOverwrite)          opts["force"]        = true
        return opts
    }

    function doConvert() {
        if (bridge.converting) return
        var opts = buildOptions()
        if (mode === 0) {
            var specs = buildFilesJobSpecs()
            if (specs.length === 0) return
            if (!advPanel.forceOverwrite) {
                // build paths/exts for collision check
                var ps = [], xs = []
                for (var k = 0; k < specs.length; k++) { ps.push(specs[k].path); xs.push(specs[k].ext) }
                var collisions = bridge.wouldOverwrite(ps, xs, "")
                if (collisions.length > 0) {
                    overwriteDialog.setup(collisions, specs, "", opts)
                    overwriteDialog.open(); return
                }
            }
            batchResults.clear()
            bridge.convertBatchDetailed(specs, "", opts)
        } else {
            var fSpecs = buildFolderJobSpecs()
            if (fSpecs.length === 0) return
            var outDir = folderSameDir ? "" : folderOutDir
            if (!advPanel.forceOverwrite) {
                var fps = [], fxs = []
                for (var m = 0; m < fSpecs.length; m++) { fps.push(fSpecs[m].path); fxs.push(fSpecs[m].ext) }
                var fc = bridge.wouldOverwrite(fps, fxs, outDir)
                if (fc.length > 0) {
                    overwriteDialog.setup(fc, fSpecs, outDir, opts)
                    overwriteDialog.open(); return
                }
            }
            batchResults.clear()
            bridge.convertBatchDetailed(fSpecs, outDir, opts)
        }
    }

    // -- Overwrite confirmation dialog -----------------------------------------
    Dialog {
        id: overwriteDialog
        modal: true
        anchors.centerIn: Overlay.overlay

        property var    _collisions: []
        property var    _specs:      []
        property string _outDir:     ""
        property var    _opts:       {}

        function setup(col, specs, outDir, opts) {
            _collisions = col; _specs = specs; _outDir = outDir; _opts = opts
        }

        background: Rectangle {
            color: root.surface; radius: 12
            border.color: root.border; border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14
            width: 380

            Text {
                Layout.fillWidth: true
                text: overwriteDialog._collisions.length + " file"
                    + (overwriteDialog._collisions.length === 1 ? "" : "s") + " will be replaced:"
                font.pixelSize: 13; font.family: root.appFont; color: root.textPrim; wrapMode: Text.Wrap
            }

            ScrollView {
                Layout.fillWidth: true
                height: Math.min(overwriteDialog._collisions.length * 22, 110)
                Column {
                    spacing: 2
                    Repeater {
                        model: overwriteDialog._collisions
                        Text {
                            width: 360
                            text: "- " + modelData.split("/").pop()
                            font.pixelSize: 11; font.family: root.appFont
                            color: root.textDim; elide: Text.ElideLeft
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: dlgCnlLbl.implicitWidth + 24; height: 34; radius: 8
                    color: dlgCnlMa.containsMouse ? root.border : root.surface
                    border.color: root.border; border.width: 1
                    Text { id: dlgCnlLbl; anchors.centerIn: parent; text: "cancel"
                        font.pixelSize: 12; font.family: root.appFont; color: root.textMid }
                    MouseArea { id: dlgCnlMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: overwriteDialog.close() }
                }
                Rectangle {
                    width: dlgRplLbl.implicitWidth + 24; height: 34; radius: 8
                    color: dlgRplMa.containsMouse ? "#d04040" : root.errorClr
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { id: dlgRplLbl; anchors.centerIn: parent; text: "replace"
                        font.pixelSize: 12; font.bold: true; font.family: root.appFont; color: "#0e0e0f" }
                    MouseArea {
                        id: dlgRplMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            overwriteDialog.close()
                            batchResults.clear()
                            var opts = Object.assign({}, overwriteDialog._opts)
                            opts["force"] = true
                            bridge.convertBatchDetailed(overwriteDialog._specs,
                                                        overwriteDialog._outDir, opts)
                        }
                    }
                }
            }
        }
    }

    // -- Native pickers (call C++ QFileDialog directly, bypasses portal) -------
    function openFilePicker() {
        var files = bridge.pickFiles("Select files")
        for (var i = 0; i < files.length; i++)
            panel.addFile(files[i])
    }

    function openFolderPicker() {
        var dir = bridge.pickFolder("Select folder to convert")
        if (dir === "") return
        scanFolderSafely(dir)
    }

    function scanFolderSafely(dir) {
        var estimate = bridge.estimateFolderSize(dir, panel.folderRecurse, 10000)
        if (estimate >= 10000) {
            largeFolderDialog.folderPath = dir
            largeFolderDialog.estimatedFiles = "10,000+"
            largeFolderDialog.open()
        } else {
            performFolderScan(dir)
        }
    }

    function performFolderScan(dir) {
        panel.folderPath = dir
        panel.folderFiles = []
        panel._folderCategories = []
        panel._folderConvertCount = 0
        panel._folderCanConvert = false
        bridge.scanFolderAsync(dir, panel.folderRecurse, 100000)
    }

    function openOutDirPicker() {
        var dir = bridge.pickFolder("Choose output folder")
        if (dir !== "") {
            panel.folderOutDir   = dir
            panel.folderSameDir  = false
        }
    }

    function openBatchOutDirPicker() {
        // (folder mode output — reuse same helper, write to folderOutDir)
        var dir = bridge.pickFolder("Choose output folder")
        if (dir !== "") {
            panel.folderOutDir  = dir
            panel.folderSameDir = false
        }
    }

    // -- Layout ----------------------------------------------------------------

    // Bottom section: convert button + batch results (always visible)
    Item {
        id: bottomSection
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.bottomMargin: 20
        height: convertRow.height + (batchResultsRect.visible ? batchResultsRect.height + 10 : 0)

        // -- Convert button ----------------------------------------------------
        Item {
            id: convertRow
            width: parent.width
            anchors.bottom: parent.bottom
            height: 44

            property bool canConvert: {
                if (bridge.converting) return false
                if (panel.mode === 0) return panel.enabledCount() > 0
                return panel._folderCanConvert
            }

            property int folderConvertCount: panel._folderConvertCount
            property int folderSkipCount: panel.folderFiles.length - folderConvertCount

            property string label: {
                if (bridge.converting) return "converting..."
                if (panel.mode === 0) {
                    var n = panel.enabledCount()
                    return n > 0 ? ("convert " + n + " file" + (n === 1 ? "" : "s") + " →") : "convert →"
                }
                var fn = folderConvertCount
                return fn > 0 ? ("convert " + fn + " file" + (fn === 1 ? "" : "s") + " →") : "convert →"
            }

            Rectangle {
                id: convertBtn
                anchors.left: parent.left
                width: Math.max(cvtLbl.implicitWidth + 32, 160)
                height: parent.height; radius: 8
                color: {
                    if (!parent.canConvert) return root.border
                    if (cvtMa.containsMouse) return root.accentDim
                    return root.accent
                }
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    id: cvtLbl; anchors.centerIn: parent; text: parent.parent.label
                    font.pixelSize: 13; font.bold: true; font.family: root.appFont
                    color: parent.parent.canConvert ? "#0e0e0f" : root.textDim
                }
                MouseArea {
                    id: cvtMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: parent.parent.canConvert ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (parent.parent.canConvert) panel.doConvert()
                }
            }

            // Skip note — folder mode only, when some files can't convert
            Text {
                anchors.left: convertBtn.right
                anchors.leftMargin: 10
                anchors.verticalCenter: convertBtn.verticalCenter
                visible: panel.mode === 1 && !bridge.converting
                         && convertRow.folderSkipCount > 0
                         && convertRow.folderConvertCount > 0
                text: convertRow.folderSkipCount + " will be skipped (unsupported)"
                font.pixelSize: 10; font.family: root.appFont; color: root.textDim
            }

            // Cancel button — only visible while converting
            Rectangle {
                anchors.left: convertBtn.right
                anchors.leftMargin: 8
                anchors.verticalCenter: convertBtn.verticalCenter
                visible: bridge.converting
                width: cancelLbl.implicitWidth + 24
                height: parent.height; radius: 8
                color: cancelMa.containsMouse ? "#a03030" : "#3a1a1a"
                border.color: root.errorClr; border.width: 1
                Behavior on color { ColorAnimation { duration: 80 } }
                Text {
                    id: cancelLbl; anchors.centerIn: parent; text: "✕  cancel"
                    font.pixelSize: 12; font.bold: true; font.family: root.appFont
                    color: root.errorClr
                }
                MouseArea {
                    id: cancelMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bridge.cancelConversion()
                }
            }
        }

        // -- Batch results -----------------------------------------------------
        Rectangle {
            id: batchResultsRect
            visible: batchResults.count > 0
            width: parent.width
            anchors.bottom: convertRow.top; anchors.bottomMargin: 10
            height: Math.min(batchList.contentHeight + 16, 180)
            color: root.surface; radius: 8; border.color: root.border; border.width: 1; clip: true

            ListView {
                id: batchList
                anchors.fill: parent; anchors.margins: 8; spacing: 3
                model: batchResults; clip: true
                delegate: RowLayout {
                    width: batchList.width; spacing: 8
                    Text { text: model.success ? "\u2713" : "\u2717"
                        font.pixelSize: 11; font.family: root.appFont
                        color: model.success ? root.success : root.errorClr }
                    Text { text: model.filename; font.pixelSize: 11; font.family: root.appFont
                        color: root.textPrim; elide: Text.ElideMiddle; Layout.preferredWidth: 180 }
                    Text { text: model.success ? ("\u2192 " + model.detail.split("/").pop()) : model.detail
                        font.pixelSize: 10; font.family: root.appFont
                        color: model.success ? root.textDim : root.errorClr
                        elide: Text.ElideLeft; Layout.fillWidth: true }
                }
            }
        }
    }

    // Top section: tabs, file/folder content, advanced options
    AdvancedPanel {
        id: advPanel
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: bottomSection.top
        anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.bottomMargin: 6
        targetExt: panel.primaryTargetExt()
        presentCategories: panel.presentCategories
    }

    ColumnLayout {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: parent.top; anchors.bottom: advPanel.top
        anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.topMargin: 12
        anchors.bottomMargin: 4
        spacing: 10

        // Mode tabs
        Row {
            spacing: 6
            Repeater {
                model: ["files", "folder"]
                delegate: Rectangle {
                    width: tabLbl.implicitWidth + 22; height: 30; radius: 8
                    color: panel.mode === index ? root.accent : (tabMa.containsMouse ? root.border : root.surface)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        id: tabLbl; anchors.centerIn: parent; text: modelData
                        font.pixelSize: 11; font.bold: true; font.family: root.appFont
                        color: panel.mode === index ? "#0e0e0f" : root.textMid
                    }
                    MouseArea {
                        id: tabMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { panel.mode = index; batchResults.clear() }
                    }
                }
            }
        }

        // -- Files mode --------------------------------------------------------
        ColumnLayout {
            visible: panel.mode === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // Empty drop zone
            Rectangle {
                visible: batchModel.count === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: emptyDropMa.containsMouse || emptyDrop.containsDrag ? root.surfaceHi : root.surface
                border.color: emptyDrop.containsDrag ? root.accent
                              : (emptyDropMa.containsMouse ? root.textDim : root.border)
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                DropArea {
                    id: emptyDrop
                    anchors.fill: parent
                    onDropped: function(drop) {
                        for (var i = 0; i < drop.urls.length; i++)
                            panel.addFile(bridge.urlToPath(drop.urls[i].toString()))
                    }
                }

                Column {
                    id: fileDropContent
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    opacity: 0
                    transform: Translate { id: fileDropSlide; y: 18 }

                    function playIn() {
                        opacity = 0; fileDropSlide.y = 18
                        fileDropInAnim.start()
                    }
                    ParallelAnimation {
                        id: fileDropInAnim
                        NumberAnimation { target: fileDropContent; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuad }
                        NumberAnimation { target: fileDropSlide; property: "y"; to: 0; duration: 220; easing.type: Easing.OutQuad }
                    }
                    Component.onCompleted: playIn()
                    Connections { target: panel; function onModeChanged() { if (panel.mode === 0) fileDropContent.playIn() } }

                    TintedIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64; height: 64
                        source: "qrc:/icons/file.svg"
                        color: root.textDim
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "drop files here or click to browse"
                        font.pixelSize: 13; font.family: root.appFont; color: root.textDim
                    }
                }
                MouseArea {
                    id: emptyDropMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: panel.openFilePicker()
                }
            }

            // Header row (when list has items)
            RowLayout {
                visible: batchModel.count > 0
                Layout.fillWidth: true; spacing: 8

                Rectangle {
                    width: addMoreLbl.implicitWidth + 16; height: 28; radius: 7
                    color: addMoreMa.containsMouse ? root.accentDim : root.accent
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { id: addMoreLbl; anchors.centerIn: parent; text: "+ add files"
                        font.pixelSize: 10; font.bold: true; font.family: root.appFont; color: "#0e0e0f" }
                    MouseArea { id: addMoreMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: panel.openFilePicker() }
                }

                DropArea {
                    Layout.fillWidth: true; height: 28
                    onDropped: function(drop) {
                        for (var i = 0; i < drop.urls.length; i++)
                            panel.addFile(bridge.urlToPath(drop.urls[i].toString()))
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 7
                        color: parent.containsDrag ? root.surfaceHi : "transparent"
                        border.color: parent.containsDrag ? root.accent : "transparent"; border.width: 1
                        Text { anchors.centerIn: parent; text: "or drop more here"
                            font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                    }
                }
            }

            // Override-all row
            RowLayout {
                visible: batchModel.count > 0
                Layout.fillWidth: true; spacing: 8

                Text {
                    text: "convert all to"
                    font.pixelSize: 10; font.bold: true; font.family: root.appFont
                    color: root.textDim; Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true; height: 32; clip: true

                    Flickable {
                        id: overrideFlick
                        anchors.fill: parent
                        contentWidth: overrideRow.implicitWidth
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        clip: true
                        Row {
                            id: overrideRow
                            y: (parent.height - height) / 2; spacing: 5
                            Rectangle {
                                width: pfLbl.implicitWidth + 14; height: 26; radius: 7
                                color: panel.overrideExt === "" ? "#50b4ff" : (pfMa.containsMouse ? root.border : root.surface)
                                border.color: panel.overrideExt === "" ? "#50b4ff" : root.border; border.width: 1
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { id: pfLbl; anchors.centerIn: parent; text: "per-file"
                                    font.pixelSize: 10; font.family: root.appFont; font.bold: panel.overrideExt === ""
                                    color: panel.overrideExt === "" ? "#0e0e0f" : root.textDim }
                                MouseArea { id: pfMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: panel.overrideExt = "" }
                            }
                            Repeater {
                                model: batchModel.count > 0 ? panel.unionFormats() : []
                                Rectangle {
                                    width: ovLbl.implicitWidth + 14; height: 26; radius: 7
                                    color: panel.overrideExt === modelData ? "#50b4ff" : (ovMa.containsMouse ? root.border : root.surface)
                                    border.color: panel.overrideExt === modelData ? "#50b4ff" : root.border; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                    Text { id: ovLbl; anchors.centerIn: parent; text: "." + modelData
                                        font.pixelSize: 11; font.family: root.appFont; font.bold: panel.overrideExt === modelData
                                        color: panel.overrideExt === modelData ? "#0e0e0f" : root.textMid }
                                    MouseArea { id: ovMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor; onClicked: panel.overrideExt = modelData }
                                }
                            }
                        }
                    }
                    AppScrollBar {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: 4; orientation: Qt.Horizontal; flickable: overrideFlick
                    }
                }
            }

            // File list
            Item {
                visible: batchModel.count > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                AppScrollBar {
                    id: fileListSB
                    anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: 4
                    orientation: Qt.Vertical
                    flickable: fileListView
                }

                ListView {
                    id: fileListView
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                              right: fileListSB.visible ? fileListSB.left : parent.right
                              rightMargin: fileListSB.visible ? 4 : 0 }
                    model: batchModel
                    spacing: 4
                    clip: true

                    property bool allEnabled: {
                        if (batchModel.count === 0) return false
                        for (var i = 0; i < batchModel.count; i++)
                            if (!batchModel.get(i).enabled) return false
                        return true
                    }

                    header: Rectangle {
                        width: fileListView.width
                        height: 32
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8
                            spacing: 8

                            // Select-all checkbox — same position as per-row checkbox
                            Rectangle {
                                width: 14; height: 14; radius: 3
                                color: fileListView.allEnabled ? "#50b4ff" : "transparent"
                                border.color: fileListView.allEnabled ? "#50b4ff" : root.accent
                                border.width: 1.5
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text {
                                    anchors.centerIn: parent; text: "\u2713"
                                    font.pixelSize: 9; font.bold: true; color: "#0e0e0f"
                                    visible: fileListView.allEnabled
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var next = !fileListView.allEnabled
                                        for (var i = 0; i < batchModel.count; i++)
                                            batchModel.setProperty(i, "enabled", next)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "file"
                                font.pixelSize: 10; font.family: root.appFont
                                color: root.textDim; font.bold: true
                            }

                            // Spacer to align with source badge + arrow + target
                            Item { width: 1; height: 1 }
                        }
                    }

                    delegate: Rectangle {
                        id: rowRect
                        width: fileListView.width
                        height: 36
                        radius: 7
                        color: rowHoverMa.containsMouse ? root.surfaceHi : root.surface
                        Behavior on color { ColorAnimation { duration: 80 } }

                        property var rowFormats: bridge.formatsFor(model.filePath)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8
                            spacing: 8

                            // Checkbox
                            Rectangle {
                                width: 14; height: 14; radius: 3
                                color: model.enabled ? "#50b4ff" : "transparent"
                                border.color: model.enabled ? "#50b4ff" : root.accent
                                border.width: 1.5
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text {
                                    anchors.centerIn: parent; text: "\u2713"
                                    font.pixelSize: 9; font.bold: true; color: "#0e0e0f"
                                    visible: model.enabled
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: batchModel.setProperty(index, "enabled", !model.enabled)
                                }
                            }

                            // Filename
                            Text {
                                Layout.fillWidth: true
                                text: model.filePath.split("/").pop().split("\\").pop()
                                font.pixelSize: 12; font.family: root.appFont
                                color: model.enabled ? root.textPrim : root.textDim
                                elide: Text.ElideMiddle
                            }

                            // Source ext badge
                            Rectangle {
                                width: srcExtLbl.implicitWidth + 10; height: 20; radius: 4
                                color: root.surfaceHi; border.color: root.border; border.width: 1
                                opacity: model.enabled ? 1.0 : 0.4
                                Text { id: srcExtLbl; anchors.centerIn: parent
                                    text: "." + model.sourceExt
                                    font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                            }

                            // Arrow
                            Text {
                                text: "\u2192"; font.pixelSize: 14
                                color: model.enabled ? root.accent : root.border
                                opacity: model.enabled ? 1.0 : 0.4
                            }

                            // Target chip
                            Rectangle {
                                id: tgtChip
                                property string eff: panel.overrideExt !== "" ? panel.overrideExt : model.targetExt
                                width: 60
                                height: 26; radius: 7
                                color: eff !== "" ? (tgtChipMa.containsMouse ? "#3fa0e8" : "#50b4ff")
                                                  : (tgtChipMa.containsMouse ? root.border : root.surfaceHi)
                                border.color: eff !== "" ? "#50b4ff" : root.border; border.width: 1
                                opacity: model.enabled ? 1.0 : 0.4
                                clip: true
                                Text {
                                    id: tgtChipLbl; anchors.centerIn: parent
                                    width: parent.width - 8
                                    text: tgtChip.eff !== "" ? ("." + tgtChip.eff) : "pick..."
                                    font.pixelSize: 11; font.family: root.appFont; font.bold: tgtChip.eff !== ""
                                    color: tgtChip.eff !== "" ? "#0e0e0f" : root.textDim
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                MouseArea {
                                    id: tgtChipMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: panel.overrideExt === "" && model.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: panel.overrideExt === "" && model.enabled
                                    onClicked: fmtPopup.openFor(index, rowRect.rowFormats, tgtChip)
                                }
                            }

                            // Gear (per-file settings)
                            Rectangle {
                                width: 22; height: 22; radius: 5
                                color: gearMa.containsMouse ? root.surfaceHi : "transparent"
                                border.color: panel.hasOverrides(index) ? root.accent : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 80 } }
                                TintedIcon {
                                    anchors.centerIn: parent
                                    width: 13; height: 13
                                    source: "qrc:/icons/cogwheel.svg"
                                    color: panel.hasOverrides(index) ? root.accent : root.textDim
                                }
                                MouseArea {
                                    id: gearMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: perFilePopup.openFor(index, rowRect)
                                }
                            }

                            // Remove button
                            Rectangle {
                                width: 28; height: 28; radius: 7
                                color: rmRowMa.containsMouse ? root.errorClr : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { anchors.centerIn: parent; text: "\u2715"
                                    font.pixelSize: 13; color: rmRowMa.containsMouse ? "#0e0e0f" : root.textDim }
                                MouseArea {
                                    id: rmRowMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        batchModel.remove(index)
                                        // If override no longer valid for all remaining files, reset it
                                        if (panel.overrideExt !== "" && panel.unionFormats().indexOf(panel.overrideExt) < 0)
                                            panel.overrideExt = ""
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: rowHoverMa; anchors.fill: parent
                            hoverEnabled: true; acceptedButtons: Qt.NoButton
                        }
                    }
                }
            }
        }

        // -- Folder mode -------------------------------------------------------
        ColumnLayout {
            visible: panel.mode === 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: panel.folderPath === ""
                Layout.preferredHeight: panel.folderPath !== "" ? 120 : -1
                radius: 8
                color: folderZoneMa.containsMouse ? root.surfaceHi : root.surface
                border.color: panel.folderPath !== "" ? root.accent
                              : (folderZoneMa.containsMouse ? root.textDim : root.border)
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }
                clip: true

                DropArea {
                    anchors.fill: parent
                    onDropped: function(drop) {
                        if (drop.urls.length > 0) {
                            var p = bridge.urlToPath(drop.urls[0].toString())
                            scanFolderSafely(p)
                        }
                    }
                }

                Column {
                    id: folderDropContent
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    opacity: 0
                    transform: Translate { id: folderDropSlide; y: 18 }

                    function playIn() {
                        opacity = 0; folderDropSlide.y = 18
                        folderDropInAnim.start()
                    }
                    ParallelAnimation {
                        id: folderDropInAnim
                        NumberAnimation { target: folderDropContent; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuad }
                        NumberAnimation { target: folderDropSlide; property: "y"; to: 0; duration: 220; easing.type: Easing.OutQuad }
                    }
                    Component.onCompleted: playIn()
                    Connections { target: panel; function onModeChanged() { if (panel.mode === 1) folderDropContent.playIn() } }

                    // Animated icon: crossfades between empty and filled state
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64; height: 64

                        TintedIcon {
                            anchors.fill: parent
                            source: "qrc:/icons/folder.svg"
                            color: root.accent
                            opacity: panel.folderPath !== "" ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                        TintedIcon {
                            anchors.fill: parent
                            source: "qrc:/icons/folder.svg"
                            color: root.textDim
                            opacity: panel.folderPath !== "" ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: panel.folderPath !== ""
                              ? (panel.folderPath.split("/").pop() || panel.folderPath)
                              : "drop a folder or click to browse"
                        font.pixelSize: 13; font.family: root.appFont
                        color: panel.folderPath !== "" ? root.textPrim : root.textDim
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
                MouseArea {
                    id: folderZoneMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: panel.openFolderPicker()
                }
            }

            RowLayout {
                visible: panel.folderPath !== ""
                Layout.fillWidth: true; spacing: 10

                Rectangle {
                    width: recLabel.implicitWidth + 24; height: 28; radius: 7
                    color: panel.folderRecurse ? root.accent : root.surface
                    border.color: panel.folderRecurse ? root.accent : root.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { id: recLabel; anchors.centerIn: parent; text: "recursive"
                        font.pixelSize: 11; font.family: root.appFont
                        color: panel.folderRecurse ? "#0e0e0f" : root.textMid }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            panel.folderRecurse = !panel.folderRecurse
                            if (panel.folderPath !== "") {
                                scanFolderSafely(panel.folderPath)
                            }
                        }
                    }
                }

                Text {
                    text: bridge.scanning ? "scanning..."
                          : (panel.folderFiles.length === 0 ? "no supported files found"
                          : (panel.folderFiles.length + " file"
                             + (panel.folderFiles.length === 1 ? "" : "s") + " found"))
                    font.pixelSize: 11; font.family: root.appFont
                    color: bridge.scanning ? root.accent
                           : (panel.folderFiles.length > 0 ? root.textMid : root.textDim)
                }
                Item { Layout.fillWidth: true }
            }

            // -- Format rules editor (when folder has files) ---------------------
            ColumnLayout {
                visible: panel.folderPath !== "" && panel.folderFiles.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                spacing: 6

                // Section header
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: "conversion rules"; font.pixelSize: 10; font.bold: true
                        font.family: root.appFont; color: root.textDim }
                    Item { Layout.fillWidth: true }
                    // Source ext quick-add chips
                    Repeater {
                        model: panel.folderFiles.length > 0 ? panel.sourcesInFolder() : []
                        Rectangle {
                            property bool hasRule: {
                                for (var i = 0; i < formatRulesModel.count; i++)
                                    if (formatRulesModel.get(i).fromExt === modelData) return true
                                return false
                            }
                            width: srcChipLbl.implicitWidth + 14; height: 22; radius: 5
                            color: hasRule ? root.surfaceHi : (srcChipMa.containsMouse ? root.border : root.surface)
                            border.color: hasRule ? root.accent : root.border; border.width: 1
                            opacity: hasRule ? 0.5 : 1.0
                            Text { id: srcChipLbl; anchors.centerIn: parent; text: "." + modelData
                                font.pixelSize: 9; font.family: root.appFont; color: root.textMid }
                            ToolTip.visible: srcChipMa.containsMouse; ToolTip.delay: 400
                            ToolTip.text: hasRule ? "rule exists for ." + modelData : "add rule for ." + modelData
                            MouseArea {
                                id: srcChipMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!parent.hasRule)
                                        addRulePopup.openFor(modelData, parent)
                                }
                            }
                        }
                    }
                }

                // Existing rules list
                Column {
                    Layout.fillWidth: true; spacing: 4
                    Repeater {
                        model: formatRulesModel
                        RowLayout {
                            width: parent.width; spacing: 8
                            property bool hasOverride: model.ovVideoCodec !== "" || model.ovAudioCodec !== ""
                                || model.ovAudioBitrate !== "" || model.ovCrf >= 0
                                || model.ovRateMode === "vbr1" || model.ovRateMode === "vbr2"
                            Text { text: "." + model.fromExt + "  \u2192"
                                font.pixelSize: 11; font.family: root.appFont; color: root.textMid }
                            Rectangle {
                                width: ruleTgtLbl.implicitWidth + 14; height: 24; radius: 5
                                color: root.surfaceHi; border.color: root.accent; border.width: 1
                                Text { id: ruleTgtLbl; anchors.centerIn: parent; text: "." + model.toExt
                                    font.pixelSize: 11; font.family: root.appFont; color: root.accent }
                            }
                            // Gear indicator for encoding overrides
                            TintedIcon {
                                visible: parent.hasOverride
                                width: 13; height: 13
                                source: "qrc:/icons/cogwheel.svg"
                                color: root.accent
                                ToolTip.visible: editRuleMa.containsMouse; ToolTip.delay: 300
                                ToolTip.text: "has encoding settings — click to edit"
                            }
                            Item { Layout.fillWidth: true }
                            // Edit button
                            Rectangle {
                                width: 20; height: 20; radius: 4
                                color: editRuleMa.containsMouse ? root.surfaceHi : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { anchors.centerIn: parent; text: "\u270e"; font.pixelSize: 10; color: root.textDim }
                                MouseArea { id: editRuleMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        addRulePopup.fromExt    = model.fromExt
                                        addRulePopup.arToExt    = model.toExt
                                        addRulePopup.arRateMode = model.ovRateMode || "crf"
                                        arVideoInput.setValue(model.ovVideoCodec || "")
                                        arAudioInput.setValue(model.ovAudioCodec || "")
                                        arCrfInput.setValue(model.ovCrf >= 0 ? model.ovCrf.toString() : "")
                                        arVbTargetInput.setValue(model.ovVideoBitrate || "")
                                        arVbMaxInput.setValue(model.ovVideoMaxRate || "")
                                        arAudioBitrateInput.setValue(model.ovAudioBitrate || "")
                                        arResolutionInput.text = model.ovResolution || ""
                                        arFramerateInput.text  = model.ovFramerate  || ""
                                        addRulePopup.reposition()
                                        addRulePopup.open()
                                    }
                                }
                            }
                            Rectangle {
                                width: 20; height: 20; radius: 4
                                color: rmRuleMa.containsMouse ? root.errorClr : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { anchors.centerIn: parent; text: "\u2715"; font.pixelSize: 10
                                    color: root.textDim }
                                MouseArea { id: rmRuleMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { formatRulesModel.remove(index); panel.recomputeFolderStats() } }
                            }
                        }
                    }
                }

                // Default (catch-all) row
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: "default:"; font.pixelSize: 10; font.bold: true
                        font.family: root.appFont; color: root.textDim }
                    Item {
                        Layout.fillWidth: true; height: 32; clip: true

                        Flickable {
                            id: folderDefaultFlick
                            anchors.fill: parent
                            contentWidth: folderDefaultRow.implicitWidth
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            clip: true

                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: function(event) {
                                    var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                                    folderDefaultFlick.contentX = Math.max(0,
                                        Math.min(folderDefaultFlick.contentWidth - folderDefaultFlick.width,
                                                 folderDefaultFlick.contentX - delta * 0.5))
                                }
                            }

                            Row {
                                id: folderDefaultRow
                                y: (parent.height - height) / 2; spacing: 5
                                Rectangle {
                                    width: nodefLbl.implicitWidth + 14; height: 26; radius: 7
                                    color: panel.folderDefaultExt === "" ? "#50b4ff" : (nodefMa.containsMouse ? root.border : root.surface)
                                    border.color: panel.folderDefaultExt === "" ? "#50b4ff" : root.border; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                    Text { id: nodefLbl; anchors.centerIn: parent; text: "skip unmatched"
                                        font.pixelSize: 10; font.family: root.appFont
                                        color: panel.folderDefaultExt === "" ? "#0e0e0f" : root.textDim }
                                    MouseArea { id: nodefMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor; onClicked: panel.folderDefaultExt = "" }
                                }
                                Repeater {
                                    model: panel.folderFormats()
                                    Rectangle {
                                        width: defExtLbl.implicitWidth + 14; height: 26; radius: 7
                                        color: panel.folderDefaultExt === modelData ? "#50b4ff" : (defExtMa.containsMouse ? root.border : root.surface)
                                        border.color: panel.folderDefaultExt === modelData ? "#50b4ff" : root.border; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { id: defExtLbl; anchors.centerIn: parent; text: "." + modelData
                                            font.pixelSize: 11; font.family: root.appFont
                                            font.bold: panel.folderDefaultExt === modelData
                                            color: panel.folderDefaultExt === modelData ? "#0e0e0f" : root.textMid }
                                        MouseArea { id: defExtMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor; onClicked: panel.folderDefaultExt = modelData }
                                    }
                                }
                            }
                        }
                        AppScrollBar {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            height: 4; orientation: Qt.Horizontal; flickable: folderDefaultFlick
                        }
                    }
                    // "+ rule" button
                    Rectangle {
                        width: addRuleLbl.implicitWidth + 16; height: 28; radius: 7
                        color: addRuleMa.containsMouse ? root.accentDim : root.accent
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: addRuleLbl; anchors.centerIn: parent; text: "+ rule"
                            font.pixelSize: 10; font.bold: true; font.family: root.appFont; color: "#0e0e0f" }
                        MouseArea { id: addRuleMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: addRulePopup.openFor("", null) }
                    }
                }

                // Folder files list (fully scrollable)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    visible: panel.folderFiles.length > 0
                    clip: true

                    AppScrollBar {
                        id: folderListSB
                        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 4; orientation: Qt.Vertical; flickable: folderPreviewList
                    }

                    ListView {
                        id: folderPreviewList
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                                  right: folderListSB.visible ? folderListSB.left : parent.right
                                  rightMargin: folderListSB.visible ? 4 : 0 }
                        model: panel.folderFiles.length
                        spacing: 2; clip: true

                        delegate: RowLayout {
                            width: folderPreviewList.width; spacing: 8
                            property string fp:  panel.folderFiles[index] || ""
                            property string tgt: fp !== "" ? panel.resolveTargetForFolder(fp) : ""
                            Text {
                                Layout.fillWidth: true
                                text: fp.split("/").pop().split("\\").pop()
                                font.pixelSize: 11; font.family: root.appFont
                                color: tgt !== "" ? root.textPrim : root.textDim; elide: Text.ElideMiddle
                            }
                            Text { text: tgt !== "" ? ("\u2192 ." + tgt) : "skip"
                                font.pixelSize: 10; font.family: root.appFont
                                color: tgt !== "" ? root.accent : root.textDim }
                        }
                    }
                }
            }

            RowLayout {
                visible: panel.folderPath !== ""
                Layout.fillWidth: true
                Layout.minimumHeight: 36
                spacing: 8

                Text { text: "output"; font.pixelSize: 10; font.bold: true
                    font.family: root.appFont; color: root.textDim; Layout.alignment: Qt.AlignVCenter }

                Rectangle {
                    width: fsdLbl.implicitWidth + 20; height: 28; radius: 7
                    color: panel.folderSameDir ? root.accent : (fsdMa.containsMouse ? root.border : root.surface)
                    border.color: panel.folderSameDir ? root.accent : root.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { id: fsdLbl; anchors.centerIn: parent; text: "same location"
                        font.pixelSize: 11; font.family: root.appFont
                        color: panel.folderSameDir ? "#0e0e0f" : root.textMid }
                    MouseArea { id: fsdMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: panel.folderSameDir = true }
                }

                Rectangle {
                    width: fcdLbl.implicitWidth + 20; height: 28; radius: 7
                    color: !panel.folderSameDir ? root.accent : (fcdMa.containsMouse ? root.border : root.surface)
                    border.color: !panel.folderSameDir ? root.accent : root.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        id: fcdLbl; anchors.centerIn: parent
                        text: !panel.folderSameDir && panel.folderOutDir !== ""
                              ? ("📁 " + panel.folderOutDir.split("/").pop())
                              : "choose folder..."
                        font.pixelSize: 11; font.family: root.appFont
                        color: !panel.folderSameDir ? "#0e0e0f" : root.textMid
                    }
                    MouseArea { id: fcdMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.openOutDirPicker() }
                }
            }
        }
    }

    // -- Per-file settings popup -----------------------------------------------
    Popup {
        id: perFilePopup
        property int    rowIdx: -1
        property string fileCategory: "Unknown"
        property string targetExt: ""
        property bool   shouldShowVideoFields: ["mp4","mkv","webm","mov","avi","ts","m4v"].indexOf(targetExt) >= 0
        property bool   shouldShowAudioFields: ["mp4","mkv","webm","mov","avi","ts","m4v","mp3","flac","wav","ogg","opus","aac","m4a"].indexOf(targetExt) >= 0
        property bool   shouldShowGifFields: targetExt === "gif"
        property bool   supportsVBR: targetExt === "mp4" || targetExt === "mkv" || targetExt === "mov" || targetExt === "webm"
            || targetExt === "avi" || targetExt === "ts" || targetExt === "m4v" || targetExt === ""
        property string pfRateMode: "crf"
        property int    animMs: 180
        property int    slidePx: 8
        modal: false
        clip: true
        padding: 14
        width: 420
        height: contentItem.implicitHeight + padding * 2 + 16

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: animMs; easing.type: Easing.OutCubic }
                NumberAnimation { property: "y"; from: perFilePopup.y - slidePx; to: perFilePopup.y; duration: animMs; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.985; to: 1.0; duration: animMs; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: animMs; easing.type: Easing.InCubic }
                NumberAnimation { property: "y"; from: perFilePopup.y; to: perFilePopup.y - slidePx; duration: animMs; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1.0; to: 0.985; duration: animMs; easing.type: Easing.InCubic }
            }
        }

        background: Rectangle {
            color: root.surfaceHi; radius: 10
            border.color: root.accent; border.width: 1
        }

        function syncRowOverrides() {
            var idx = rowIdx
            if (idx < 0 || idx >= batchModel.count) return
            batchModel.setProperty(idx, "outputName",     pfNameInput.text)
            batchModel.setProperty(idx, "ovVideoCodec",   pfVideoInput.value)
            batchModel.setProperty(idx, "ovAudioCodec",   pfAudioInput.value)
            batchModel.setProperty(idx, "ovRateMode",     pfRateMode)
            batchModel.setProperty(idx, "ovVideoBitrate", pfVideoBitrateInput.value)
            batchModel.setProperty(idx, "ovVideoMaxRate", pfVideoMaxRateInput.value)
            batchModel.setProperty(idx, "ovAudioBitrate", pfAudioBitrateInput.value)
            batchModel.setProperty(idx, "ovCrf", pfRateMode === "crf" && pfCrfInput.value.length > 0 ? parseInt(pfCrfInput.value) : -1)
            batchModel.setProperty(idx, "ovResolution",   pfResolutionInput.text)
            batchModel.setProperty(idx, "ovFramerate",    pfFramerateInput.text)
        }

        function scheduleSync() {
            syncDebounce.restart()
        }

        Timer {
            id: syncDebounce
            interval: 120
            repeat: false
            onTriggered: perFilePopup.syncRowOverrides()
        }

        function openFor(idx, anchor) {
            rowIdx = idx
            var item = batchModel.get(idx)
            fileCategory = bridge.categoryFor(item.sourceExt)
            targetExt    = panel.effectiveTarget(idx)
            pfRateMode   = item.ovRateMode || "crf"
            pfNameInput.text              = item.outputName
            pfVideoInput.setValue(item.ovVideoCodec)
            pfAudioInput.setValue(item.ovAudioCodec)
            pfVideoBitrateInput.setValue(item.ovVideoBitrate)
            pfVideoMaxRateInput.setValue(item.ovVideoMaxRate || "")
            pfAudioBitrateInput.setValue(item.ovAudioBitrate)
            pfCrfInput.setValue(item.ovCrf >= 0 ? item.ovCrf.toString() : "")
            pfResolutionInput.text = item.ovResolution || ""
            pfFramerateInput.text = item.ovFramerate || ""
            var pos = anchor.mapToItem(panel, 0, anchor.height + 4)
            x = Math.min(Math.max(pos.x, 4), panel.width - implicitWidth - 4)
            y = Math.min(pos.y, panel.height - implicitHeight - 4)
            open()
        }

        contentItem: ColumnLayout {
            spacing: 10
            width: 392

            Text { text: perFilePopup.rowIdx >= 0 && perFilePopup.rowIdx < batchModel.count
                        ? batchModel.get(perFilePopup.rowIdx).filePath.split("/").pop().split("\\").pop()
                        : ""
                font.pixelSize: 11; font.bold: true; font.family: root.appFont
                color: root.textPrim; elide: Text.ElideMiddle; Layout.fillWidth: true }

            Row {
                visible: perFilePopup.shouldShowVideoFields && perFilePopup.supportsVBR
                Layout.preferredHeight: visible ? 32 : 0
                Behavior on Layout.preferredHeight { NumberAnimation { duration: animMs; easing.type: Easing.InOutCubic } }
                spacing: 6
                Repeater {
                    model: [
                        { id: "crf",  label: "CRF" },
                        { id: "vbr1", label: "VBR 1-pass" },
                        { id: "vbr2", label: "VBR 2-pass" },
                    ]
                    Rectangle {
                        property bool active: perFilePopup.pfRateMode === modelData.id
                        width: 88; height: 26; radius: 7
                        scale: active ? 1.0 : (pfRmMa.pressed ? 0.975 : 1.0)
                        color: active ? root.accent : (pfRmMa.containsMouse ? root.surfaceHi : root.surface)
                        border.color: active ? root.accent : root.border; border.width: active ? 1.5 : 1
                        Behavior on color { ColorAnimation { duration: animMs; easing.type: Easing.InOutCubic } }
                        Behavior on border.color { ColorAnimation { duration: animMs; easing.type: Easing.InOutCubic } }
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Text { anchors.centerIn: parent; text: modelData.label
                            font.pixelSize: 10; font.family: root.appFont; font.bold: active
                            color: active ? "#0e0e0f" : root.textDim }
                        MouseArea { id: pfRmMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                perFilePopup.pfRateMode = modelData.id
                                if (modelData.id === "crf") {
                                    pfVideoBitrateInput.setValue("")
                                    pfVideoMaxRateInput.setValue("")
                                } else {
                                    pfCrfInput.setValue("")
                                }
                                perFilePopup.syncRowOverrides()
                            }
                        }
                    }
                }
            }

            GridLayout { columns: 2; columnSpacing: 10; rowSpacing: 8
                Text { text: "output name"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: pfNameInput.activeFocus ? root.accent : root.border; border.width: 1; clip: true
                    TextInput {
                        id: pfNameInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        onTextEdited: perFilePopup.scheduleSync()
                        onEditingFinished: perFilePopup.syncRowOverrides()
                        Text { visible: !parent.text.length; anchors.fill: parent; text: "keep original"
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim; elide: Text.ElideRight }
                    }
                }
                Text { text: "video codec"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: perFilePopup.shouldShowVideoFields; Layout.preferredHeight: visible ? implicitHeight : 0 }
                FieldDropdown {
                    id: pfVideoInput
                    visible: perFilePopup.shouldShowVideoFields
                    Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true
                    hint: "global default"
                    onValueChanged: perFilePopup.syncRowOverrides()
                    options: {
                        var tgt = perFilePopup.rowIdx >= 0 && perFilePopup.rowIdx < batchModel.count
                                  ? panel.effectiveTarget(perFilePopup.rowIdx) : ""
                        if (tgt === "webm") return ["libvpx-vp9","libvpx","libaom-av1"]
                        if (tgt === "mov")  return ["libx264","libx265","prores_ks","h264_videotoolbox","copy"]
                        if (tgt === "avi")  return ["mpeg4","libx264","libxvid","copy"]
                        if (tgt === "mkv")  return ["libx264","libx265","libvpx-vp9","libaom-av1","h264_nvenc","hevc_nvenc","copy"]
                        return ["libx264","libx265","libaom-av1","h264_nvenc","hevc_nvenc","h264_videotoolbox","libvpx-vp9","prores_ks","mpeg4","copy"]
                    }
                }
                Item {
                    visible: perFilePopup.shouldShowVideoFields
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    clip: true
                    Layout.preferredHeight: visible
                                            ? (perFilePopup.pfRateMode === "crf"
                                               ? rateCrfPanel.implicitHeight
                                               : rateVbrPanel.implicitHeight)
                                            : 0
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: animMs; easing.type: Easing.InOutCubic } }

                    GridLayout {
                        id: rateCrfPanel
                        anchors.fill: parent
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 8
                        enabled: perFilePopup.pfRateMode === "crf"
                        opacity: perFilePopup.pfRateMode === "crf" ? 1 : 0
                        y: perFilePopup.pfRateMode === "crf" ? 0 : 6
                        Behavior on opacity { NumberAnimation { duration: animMs; easing.type: Easing.InOutQuad } }
                        Behavior on y { NumberAnimation { duration: animMs; easing.type: Easing.InOutQuad } }

                        Text {
                            text: "CRF"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                            Layout.preferredWidth: Math.max(pfLabelWidthRef.implicitWidth, implicitWidth)
                        }
                        FieldDropdown {
                            id: pfCrfInput
                            Layout.preferredHeight: 28
                            Layout.fillWidth: true
                            hint: "global default"
                            onValueChanged: perFilePopup.syncRowOverrides()
                            options: ["16","17","18","19","20","21","22","23","24","26","28","30","31","35","40"]
                        }
                    }

                    GridLayout {
                        id: rateVbrPanel
                        anchors.fill: parent
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 8
                        enabled: perFilePopup.pfRateMode !== "crf"
                        opacity: perFilePopup.pfRateMode !== "crf" ? 1 : 0
                        y: perFilePopup.pfRateMode !== "crf" ? 0 : 6
                        Behavior on opacity { NumberAnimation { duration: animMs; easing.type: Easing.InOutQuad } }
                        Behavior on y { NumberAnimation { duration: animMs; easing.type: Easing.InOutQuad } }

                        Text {
                            text: "target bitrate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                            Layout.preferredWidth: Math.max(pfLabelWidthRef.implicitWidth, implicitWidth)
                        }
                        FieldDropdown {
                            id: pfVideoBitrateInput
                            Layout.preferredHeight: 28
                            Layout.fillWidth: true
                            hint: "4M, 8M"
                            onValueChanged: perFilePopup.syncRowOverrides()
                            options: ["500k","1M","2M","3M","4M","6M","8M","12M","15M","20M","30M","40M"]
                        }

                        Text {
                            text: "max bitrate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                            Layout.preferredWidth: Math.max(pfLabelWidthRef.implicitWidth, implicitWidth)
                        }
                        FieldDropdown {
                            id: pfVideoMaxRateInput
                            Layout.preferredHeight: 28
                            Layout.fillWidth: true
                            hint: "leave blank or 2× target"
                            onValueChanged: perFilePopup.syncRowOverrides()
                            options: ["","1M","2M","4M","6M","8M","12M","16M","20M","30M","50M","60M"]
                        }
                    }
                }
                Text { text: "audio codec"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: perFilePopup.shouldShowAudioFields; Layout.preferredHeight: visible ? implicitHeight : 0 }
                FieldDropdown {
                    id: pfAudioInput
                    visible: perFilePopup.shouldShowAudioFields
                    Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true
                    hint: "global default"
                    onValueChanged: perFilePopup.syncRowOverrides()
                    options: {
                        var tgt = perFilePopup.rowIdx >= 0 && perFilePopup.rowIdx < batchModel.count
                                  ? panel.effectiveTarget(perFilePopup.rowIdx) : ""
                        if (tgt === "webm" || tgt === "opus") return ["libopus","libvorbis"]
                        if (tgt === "ogg")  return ["libvorbis","libopus"]
                        if (tgt === "mp3")  return ["libmp3lame"]
                        if (tgt === "flac") return ["flac"]
                        if (tgt === "wav")  return ["pcm_s16le","pcm_s24le","pcm_f32le"]
                        if (tgt === "aac" || tgt === "m4a") return ["aac","libfdk_aac"]
                        if (tgt === "mov")  return ["aac","pcm_s16le","copy"]
                        return ["aac","libopus","libmp3lame","flac","libvorbis","pcm_s16le","pcm_s24le","copy"]
                    }
                }
                Text { id: pfLabelWidthRef; text: "audio bitrate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: perFilePopup.shouldShowAudioFields; Layout.preferredHeight: visible ? implicitHeight : 0 }
                FieldDropdown {
                    id: pfAudioBitrateInput
                    visible: perFilePopup.shouldShowAudioFields
                    Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true
                    hint: "global default"
                    onValueChanged: perFilePopup.syncRowOverrides()
                    options: ["64k","96k","128k","192k","256k","320k"]
                }
                Text { text: "resolution"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: perFilePopup.shouldShowGifFields; Layout.preferredHeight: visible ? implicitHeight : 0 }
                Rectangle {
                    visible: perFilePopup.shouldShowGifFields
                    Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: pfResolutionInput.activeFocus ? root.accent : root.border; border.width: 1; clip: true
                    TextInput {
                        id: pfResolutionInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        onTextEdited: perFilePopup.scheduleSync()
                        onEditingFinished: perFilePopup.syncRowOverrides()
                        Text { visible: !parent.text.length; anchors.fill: parent; text: "keep source"
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim; elide: Text.ElideRight }
                    }
                }
                Text { text: "framerate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: perFilePopup.shouldShowGifFields; Layout.preferredHeight: visible ? implicitHeight : 0 }
                Rectangle {
                    visible: perFilePopup.shouldShowGifFields
                    Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: pfFramerateInput.activeFocus ? root.accent : root.border; border.width: 1; clip: true
                    TextInput {
                        id: pfFramerateInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        onTextEdited: perFilePopup.scheduleSync()
                        onEditingFinished: perFilePopup.syncRowOverrides()
                        Text { visible: !parent.text.length; anchors.fill: parent; text: "keep source"
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim; elide: Text.ElideRight }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Layout.preferredHeight: 30
                // Clear overrides button
                Rectangle {
                    width: pfClrLbl.implicitWidth + 16; height: 30; radius: 7
                    color: pfClrMa.containsMouse ? root.surfaceHi : root.surface
                    border.color: root.border; border.width: 1
                    Text { id: pfClrLbl; anchors.centerIn: parent; text: "clear"
                        font.pixelSize: 11; font.family: root.appFont; color: root.textDim }
                    MouseArea { id: pfClrMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pfNameInput.text = ""
                            pfVideoInput.setValue("")
                            pfAudioInput.setValue("")
                            perFilePopup.pfRateMode = "crf"
                            pfVideoBitrateInput.setValue("")
                            pfVideoMaxRateInput.setValue("")
                            pfAudioBitrateInput.setValue("")
                            pfCrfInput.setValue("")
                            pfResolutionInput.text = ""
                            pfFramerateInput.text = ""
                            perFilePopup.syncRowOverrides()
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // -- Add-rule popup --------------------------------------------------------
    Popup {
        id: addRulePopup
        property string fromExt:    ""
        property string arToExt:    ""
        property string arRateMode: "crf"
        property int    animMs:     180
        property int    slidePx:    8

        modal: false
        padding: 14
        width: 440
        clip: true

        // Smooth height: animate to content size, capped at panel height
        property real targetH: Math.min(arContentCol.implicitHeight + padding * 2 + 16, panel.height - 20)
        height: targetH
        Behavior on targetH { NumberAnimation { duration: addRulePopup.animMs; easing.type: Easing.InOutCubic } }

        property bool arShowVideo: ["mp4","mkv","webm","mov","avi","ts","m4v"].indexOf(arToExt) >= 0
        property bool arShowAudio: ["mp4","mkv","webm","mov","avi","ts","m4v","mp3","flac","wav","ogg","opus","aac","m4a"].indexOf(arToExt) >= 0
        property bool arShowGif:   arToExt === "gif"
        property bool arSupportsVBR: ["mp4","mkv","mov","webm","avi","ts","m4v",""].indexOf(arToExt) >= 0

        // Valid target formats for the current fromExt
        property var validTargets: {
            var from = fromExt
            if (from === "") return []
            for (var i = 0; i < panel.folderFiles.length; i++) {
                if (bridge.detectFormat(panel.folderFiles[i]) === from)
                    return bridge.formatsFor(panel.folderFiles[i])
            }
            return bridge.formatsFor("file." + from)
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: addRulePopup.animMs; easing.type: Easing.OutCubic }
                NumberAnimation { property: "y"; from: addRulePopup.y - addRulePopup.slidePx; to: addRulePopup.y; duration: addRulePopup.animMs; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: addRulePopup.animMs; easing.type: Easing.InCubic }
                NumberAnimation { property: "y"; from: addRulePopup.y; to: addRulePopup.y - addRulePopup.slidePx; duration: addRulePopup.animMs; easing.type: Easing.InCubic }
            }
        }

        background: Rectangle {
            color: root.surfaceHi; radius: 10
            border.color: root.accent; border.width: 1
        }

        function reposition() {
            x = Math.max(4, Math.min(panel.width  - width  - 4, panel.width  / 2 - width  / 2))
            y = Math.max(4, Math.min(panel.height - height - 4, panel.height / 2 - height / 2))
        }

        onTargetHChanged: if (visible) reposition()

        function openFor(srcExt, anchor) {
            fromExt    = srcExt
            arToExt    = ""
            arRateMode = "crf"
            arVideoInput.setValue("")
            arAudioInput.setValue("")
            arCrfInput.setValue("")
            arVbTargetInput.setValue("")
            arVbMaxInput.setValue("")
            arAudioBitrateInput.setValue("")
            arResolutionInput.text = ""
            arFramerateInput.text  = ""
            reposition()
            open()
        }

        contentItem: ScrollView {
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            ColumnLayout {
            id: arContentCol
            spacing: 10
            width: addRulePopup.width - addRulePopup.padding * 2 - 12

            // Header row: from → to
            RowLayout {
                Layout.fillWidth: true; spacing: 8

                // From ext (display-only when pre-filled, editable otherwise)
                ColumnLayout { spacing: 4
                    Text { text: "from"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                    Rectangle {
                        width: 80; height: 30; radius: 6
                        color: root.surface; border.color: arFromTI.activeFocus ? root.accent : root.border; border.width: 1
                        TextInput {
                            id: arFromTI; anchors.fill: parent; anchors.margins: 6
                            text: addRulePopup.fromExt
                            font.pixelSize: 12; font.family: root.appFont; color: root.textPrim
                            onTextEdited: addRulePopup.fromExt = text.trim().replace(/^\./, "")
                            Text { visible: !parent.text.length; anchors.fill: parent; text: "mp4"
                                font.pixelSize: 12; font.family: root.appFont; color: root.textDim }
                        }
                    }
                }

                Text { text: "\u2192"; font.pixelSize: 18; color: root.textDim
                    Layout.alignment: Qt.AlignBottom; bottomPadding: 6 }

                // To ext — dropdown of valid target formats for this fromExt
                ColumnLayout { spacing: 4; Layout.fillWidth: true
                    Text { text: "to"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }

                    Rectangle {
                        id: arToDropBtn
                        Layout.fillWidth: true; height: 30; radius: 6
                        color: root.surface
                        border.color: addRulePopup.arToExt !== "" ? root.accent : root.border; border.width: 1

                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: addRulePopup.arToExt !== "" ? ("." + addRulePopup.arToExt) : "pick format…"
                                font.pixelSize: 12; font.family: root.appFont
                                color: addRulePopup.arToExt !== "" ? root.textPrim : root.textDim
                            }
                            Text { text: "▾"; font.pixelSize: 10; color: root.textDim }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Position picker below this button in panel-local coords
                                var pos = arToDropBtn.mapToItem(panel, 0, arToDropBtn.height + 4)
                                arFormatPicker.x = Math.min(Math.max(pos.x, 4), panel.width - arFormatPicker.width - 4)
                                var py = pos.y
                                if (py + arFormatPicker.height > panel.height - 4)
                                    py = arToDropBtn.mapToItem(panel, 0, -arFormatPicker.height - 4).y
                                arFormatPicker.y = Math.max(4, py)
                                arFormatPicker.open()
                            }
                        }
                    }
                }
            }

            // Rate mode tabs (video only)
            Row {
                visible: addRulePopup.arShowVideo && addRulePopup.arSupportsVBR
                Layout.preferredHeight: visible ? 32 : 0
                Behavior on Layout.preferredHeight { NumberAnimation { duration: addRulePopup.animMs; easing.type: Easing.InOutCubic } }
                spacing: 6
                Repeater {
                    model: [{ id: "crf", label: "CRF" }, { id: "vbr1", label: "VBR 1-pass" }, { id: "vbr2", label: "VBR 2-pass" }]
                    Rectangle {
                        property bool active: addRulePopup.arRateMode === modelData.id
                        width: 88; height: 26; radius: 7
                        color: active ? root.accent : (arRmMa.containsMouse ? root.surfaceHi : root.surface)
                        border.color: active ? root.accent : root.border; border.width: active ? 1.5 : 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData.label
                            font.pixelSize: 10; font.family: root.appFont; font.bold: active
                            color: active ? "#0e0e0f" : root.textDim }
                        MouseArea { id: arRmMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                addRulePopup.arRateMode = modelData.id
                                if (modelData.id === "crf") {
                                    arVbTargetInput.setValue(""); arVbMaxInput.setValue("")
                                } else {
                                    arCrfInput.setValue("")
                                }
                            }
                        }
                    }
                }
            }

            // Encoding fields grid
            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 8
                Layout.fillWidth: true

                Text { text: "video codec"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: addRulePopup.arShowVideo; Layout.preferredHeight: visible ? implicitHeight : 0 }
                FieldDropdown {
                    id: arVideoInput
                    visible: addRulePopup.arShowVideo; Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true; hint: "global default"
                    options: {
                        var t = addRulePopup.arToExt
                        if (t === "webm") return ["libvpx-vp9","libvpx","libaom-av1"]
                        if (t === "mov")  return ["libx264","libx265","prores_ks","h264_videotoolbox","copy"]
                        if (t === "avi")  return ["mpeg4","libx264","libxvid","copy"]
                        if (t === "mkv")  return ["libx264","libx265","libvpx-vp9","libaom-av1","h264_nvenc","hevc_nvenc","copy"]
                        return ["libx264","libx265","libaom-av1","h264_nvenc","hevc_nvenc","h264_videotoolbox","copy"]
                    }
                }

                Item {
                    visible: addRulePopup.arShowVideo; Layout.columnSpan: 2
                    Layout.fillWidth: true; clip: true
                    Layout.preferredHeight: visible
                        ? (addRulePopup.arRateMode === "crf" ? arRateCrfPanel.implicitHeight : arRateVbrPanel.implicitHeight)
                        : 0
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: addRulePopup.animMs; easing.type: Easing.InOutCubic } }

                    // CRF panel — label above, full-width dropdown (matches audio codec style)
                    Column {
                        id: arRateCrfPanel
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        spacing: 4
                        opacity: addRulePopup.arRateMode === "crf" ? 1 : 0
                        enabled: addRulePopup.arRateMode === "crf"
                        y: addRulePopup.arRateMode === "crf" ? 0 : 6
                        Behavior on opacity { NumberAnimation { duration: addRulePopup.animMs; easing.type: Easing.InOutQuad } }
                        Behavior on y      { NumberAnimation { duration: addRulePopup.animMs; easing.type: Easing.InOutQuad } }
                        Text { text: "crf"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                        FieldDropdown { id: arCrfInput; width: parent.width; height: 28
                            hint: "global default"
                            options: ["16","17","18","19","20","21","22","23","24","26","28","30","31","35","40"] }
                    }
                    // VBR panel — label above, full-width dropdowns
                    Column {
                        id: arRateVbrPanel
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        spacing: 4
                        opacity: addRulePopup.arRateMode !== "crf" ? 1 : 0
                        enabled: addRulePopup.arRateMode !== "crf"
                        y: addRulePopup.arRateMode !== "crf" ? 0 : 6
                        Behavior on opacity { NumberAnimation { duration: addRulePopup.animMs; easing.type: Easing.InOutQuad } }
                        Behavior on y      { NumberAnimation { duration: addRulePopup.animMs; easing.type: Easing.InOutQuad } }
                        Text { text: "target bitrate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                        FieldDropdown { id: arVbTargetInput; width: parent.width; height: 28
                            hint: "4M, 8M"
                            options: ["500k","1M","2M","3M","4M","6M","8M","12M","15M","20M","30M","40M"] }
                        Text { text: "max bitrate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                        FieldDropdown { id: arVbMaxInput; width: parent.width; height: 28
                            hint: "leave blank or 2× target"
                            options: ["","1M","2M","4M","6M","8M","12M","16M","20M","30M","50M","60M"] }
                    }
                }

                Text { text: "audio codec"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: addRulePopup.arShowAudio; Layout.preferredHeight: visible ? implicitHeight : 0 }
                FieldDropdown { id: arAudioInput
                    visible: addRulePopup.arShowAudio; Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true; hint: "global default"
                    options: {
                        var t = addRulePopup.arToExt
                        if (t === "webm" || t === "opus") return ["libopus","libvorbis"]
                        if (t === "ogg")  return ["libvorbis","libopus"]
                        if (t === "mp3")  return ["libmp3lame"]
                        if (t === "flac") return ["flac"]
                        if (t === "wav")  return ["pcm_s16le","pcm_s24le","pcm_f32le"]
                        if (t === "aac" || t === "m4a") return ["aac","libfdk_aac"]
                        if (t === "mov")  return ["aac","pcm_s16le","copy"]
                        return ["aac","libopus","libmp3lame","flac","libvorbis","pcm_s16le","pcm_s24le","copy"]
                    }
                }

                Text { text: "audio bitrate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: addRulePopup.arShowAudio; Layout.preferredHeight: visible ? implicitHeight : 0 }
                FieldDropdown { id: arAudioBitrateInput
                    visible: addRulePopup.arShowAudio; Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true; hint: "global default"
                    options: ["64k","96k","128k","192k","256k","320k"] }

                Text { text: "resolution"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: addRulePopup.arShowGif; Layout.preferredHeight: visible ? implicitHeight : 0 }
                Rectangle { visible: addRulePopup.arShowGif; Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: arResolutionInput.activeFocus ? root.accent : root.border; border.width: 1; clip: true
                    TextInput { id: arResolutionInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        Text { visible: !parent.text.length; anchors.fill: parent; text: "keep source"
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim } } }

                Text { text: "framerate"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                    visible: addRulePopup.arShowGif; Layout.preferredHeight: visible ? implicitHeight : 0 }
                Rectangle { visible: addRulePopup.arShowGif; Layout.preferredHeight: visible ? 28 : 0
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: arFramerateInput.activeFocus ? root.accent : root.border; border.width: 1; clip: true
                    TextInput { id: arFramerateInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        Text { visible: !parent.text.length; anchors.fill: parent; text: "keep source"
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim } } }
            }

            // Buttons
            RowLayout { spacing: 8; Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: arCnlLbl.implicitWidth + 16; height: 30; radius: 7
                    color: arCnlMa.containsMouse ? root.surfaceHi : root.surface
                    border.color: root.border; border.width: 1
                    Text { id: arCnlLbl; anchors.centerIn: parent; text: "cancel"
                        font.pixelSize: 11; font.family: root.appFont; color: root.textDim }
                    MouseArea { id: arCnlMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: addRulePopup.close() }
                }
                Rectangle {
                    property bool canAdd: addRulePopup.fromExt.trim() !== "" && addRulePopup.arToExt !== ""
                    width: arAddLbl.implicitWidth + 20; height: 30; radius: 7
                    color: canAdd ? (arAddMa.containsMouse ? root.accentDim : root.accent) : root.border
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { id: arAddLbl; anchors.centerIn: parent; text: "add rule"
                        font.pixelSize: 11; font.bold: true; font.family: root.appFont; color: "#0e0e0f" }
                    MouseArea {
                        id: arAddMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: parent.canAdd ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!parent.canAdd) return
                            var from = addRulePopup.fromExt.trim().replace(/^\./, "")
                            var to   = addRulePopup.arToExt
                            if (from === "" || to === "") return
                            // Remove any existing rule for this from ext
                            for (var i = formatRulesModel.count - 1; i >= 0; i--)
                                if (formatRulesModel.get(i).fromExt === from) formatRulesModel.remove(i)
                            // Build encoding fields
                            var crf = (addRulePopup.arRateMode === "crf" && arCrfInput.value !== "") ? parseInt(arCrfInput.value) : -1
                            formatRulesModel.append({
                                fromExt: from, toExt: to,
                                ovVideoCodec:   arVideoInput.value,
                                ovAudioCodec:   arAudioInput.value,
                                ovRateMode:     addRulePopup.arRateMode,
                                ovVideoBitrate: arVbTargetInput.value,
                                ovVideoMaxRate: arVbMaxInput.value,
                                ovAudioBitrate: arAudioBitrateInput.value,
                                ovCrf:          crf,
                                ovResolution:   arResolutionInput.text,
                                ovFramerate:    arFramerateInput.text
                            })
                            panel.recomputeFolderStats()
                            addRulePopup.close()
                        }
                    }
                }
            }
        }
        } // ScrollView
    }

    // -- Format target picker (top-level so coordinates are correct) -----------
    Popup {
        id: arFormatPicker
        modal: false
        padding: 8
        width: 300
        height: Math.min(arFmtCol.implicitHeight + 20, 340)
        clip: true

        background: Rectangle {
            color: root.surface; radius: 8
            border.color: root.border; border.width: 1
        }

        ScrollView {
            anchors.fill: parent; clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            Column {
                id: arFmtCol
                width: arFormatPicker.width - 20
                spacing: 8
                Repeater {
                    model: bridge.allFormatsGrouped()
                    delegate: Column {
                        width: parent.width; spacing: 4

                        // Only show the group if it has any valid targets
                        property var filtered: {
                            var valid = addRulePopup.validTargets
                            var result = []
                            for (var i = 0; i < modelData.exts.length; i++)
                                if (valid.indexOf(modelData.exts[i]) >= 0)
                                    result.push(modelData.exts[i])
                            return result
                        }
                        visible: filtered.length > 0

                        Text { text: modelData.icon + "  " + modelData.name
                            font.pixelSize: 10; font.bold: true; font.family: root.appFont
                            color: root.textDim; leftPadding: 2 }
                        Flow {
                            width: parent.width; spacing: 4
                            Repeater {
                                model: parent.parent.filtered
                                Rectangle {
                                    property bool isSel: addRulePopup.arToExt === modelData
                                    width: fmtChipLbl.implicitWidth + 14; height: 24; radius: 6
                                    color: isSel ? "#50b4ff" : (fmtChipMa.containsMouse ? root.border : root.surfaceHi)
                                    border.color: isSel ? "#50b4ff" : root.border; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 60 } }
                                    Text { id: fmtChipLbl; anchors.centerIn: parent
                                        text: "." + modelData
                                        font.pixelSize: 10; font.family: root.appFont; font.bold: isSel
                                        color: isSel ? "#0e0e0f" : root.textMid }
                                    MouseArea { id: fmtChipMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            addRulePopup.arToExt = modelData
                                            addRulePopup.arRateMode = "crf"
                                            arVideoInput.setValue("")
                                            arAudioInput.setValue("")
                                            arCrfInput.setValue("")
                                            arVbTargetInput.setValue("")
                                            arVbMaxInput.setValue("")
                                            arAudioBitrateInput.setValue("")
                                            arFormatPicker.close()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Large folder warning dialog ───────────────────────────────────────────
    Popup {
        id: largeFolderDialog
        property string folderPath: ""
        property string estimatedFiles: ""
        
        anchors.centerIn: parent
        width: 440
        padding: 0
        modal: true
        closePolicy: Popup.CloseOnEscape
        
        background: Rectangle {
            color: root.surface
            radius: 12
            border.color: root.border
            border.width: 1
        }
        
        Column {
            width: parent.width
            spacing: 0
            
            // Header
            Rectangle {
                width: parent.width
                height: 54
                color: "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "⚠️  Large Folder Detected"
                    font.pixelSize: 14
                    font.bold: true
                    font.family: root.appFont
                    color: root.textPrim
                }
            }
            
            // Content
            Column {
                width: parent.width
                spacing: 14
                topPadding: 10
                leftPadding: 24
                rightPadding: 24
                bottomPadding: 10
                
                Text {
                    width: parent.width - 48
                    wrapMode: Text.WordWrap
                    text: "This folder contains " + largeFolderDialog.estimatedFiles + " files."
                    font.pixelSize: 12
                    font.family: root.appFont
                    color: root.textMid
                }
                
                Text {
                    width: parent.width - 48
                    wrapMode: Text.WordWrap
                    text: "Scanning large folders may take a while and could slow down the application. Do you want to continue?"
                    font.pixelSize: 12
                    font.family: root.appFont
                    color: root.textMid
                }
            }
            
            // Buttons
            Item {
                width: parent.width
                height: 70
                
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    
                    Rectangle {
                        width: 96; height: 36; radius: 7
                        color: largeFolderCancelMa.containsMouse ? root.border : root.surface
                        border.color: root.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: 12
                            font.family: root.appFont
                            color: root.textMid
                        }
                        MouseArea {
                            id: largeFolderCancelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: largeFolderDialog.close()
                        }
                    }
                    
                    Rectangle {
                        width: 96; height: 36; radius: 7
                        color: continueMa.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text {
                            anchors.centerIn: parent
                            text: "Continue"
                            font.pixelSize: 12
                            font.family: root.appFont
                            color: "#0e0e0f"
                        }
                        MouseArea {
                            id: continueMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                performFolderScan(largeFolderDialog.folderPath)
                                largeFolderDialog.close()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Scan limit reached dialog ─────────────────────────────────────────────
    Popup {
        id: scanLimitDialog
        anchors.centerIn: parent
        width: 440
        padding: 0
        modal: true
        closePolicy: Popup.CloseOnEscape
        
        background: Rectangle {
            color: root.surface
            radius: 12
            border.color: root.border
            border.width: 1
        }
        
        Column {
            width: parent.width
            spacing: 0
            
            // Header
            Rectangle {
                width: parent.width
                height: 54
                color: "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "ℹ️  Scan Limit Reached"
                    font.pixelSize: 14
                    font.bold: true
                    font.family: root.appFont
                    color: root.textPrim
                }
            }
            
            // Content
            Column {
                width: parent.width
                spacing: 14
                topPadding: 10
                leftPadding: 24
                rightPadding: 24
                bottomPadding: 10
                
                Text {
                    width: parent.width - 48
                    wrapMode: Text.WordWrap
                    text: "The folder scan stopped at 100,000 files to prevent performance issues."
                    font.pixelSize: 12
                    font.family: root.appFont
                    color: root.textMid
                }
                
                Text {
                    width: parent.width - 48
                    wrapMode: Text.WordWrap
                    text: "Only the first 100,000 supported files will be available for conversion."
                    font.pixelSize: 12
                    font.family: root.appFont
                    color: root.textMid
                }
            }
            
            // Button
            Item {
                width: parent.width
                height: 70
                
                Rectangle {
                    anchors.centerIn: parent
                    width: 96; height: 36; radius: 7
                    color: okMa.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        font.pixelSize: 12
                        font.family: root.appFont
                        color: "#0e0e0f"
                    }
                    MouseArea {
                        id: okMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: scanLimitDialog.close()
                    }
                }
            }
        }
    }

    Popup {
        id: fmtPopup
        property int rowIndex: -1
        property var formats:  []
        padding: 10

        background: Rectangle {
            color: root.surfaceHi; radius: 10
            border.color: root.border; border.width: 1
        }

        function openFor(idx, fmts, anchor) {
            rowIndex = idx
            formats  = fmts
            var pos  = anchor.mapToItem(panel, 0, anchor.height + 4)
            x = Math.min(pos.x, panel.width - implicitWidth - 12)
            y = pos.y
            open()
        }

        contentItem: Flow {
            width: 260; spacing: 6
            Repeater {
                model: fmtPopup.formats
                Rectangle {
                    property bool isCur: fmtPopup.rowIndex >= 0
                                         && fmtPopup.rowIndex < batchModel.count
                                         && batchModel.get(fmtPopup.rowIndex).targetExt === modelData
                    width: ppLbl.implicitWidth + 14; height: 28; radius: 7
                    color: isCur ? "#50b4ff" : (ppMa.containsMouse ? root.border : root.surface)
                    border.color: isCur ? "#50b4ff" : root.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { id: ppLbl; anchors.centerIn: parent; text: "." + modelData
                        font.pixelSize: 11; font.family: root.appFont; font.bold: isCur
                        color: isCur ? "#0e0e0f" : root.textMid }
                    MouseArea {
                        id: ppMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            batchModel.setProperty(fmtPopup.rowIndex, "targetExt", modelData)
                            fmtPopup.close()
                        }
                    }
                }
            }
        }
    }
}