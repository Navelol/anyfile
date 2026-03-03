import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: panel

    // mode: 0 = files/batch, 1 = folder
    property int mode: 0

    // -- Batch model -----------------------------------------------------------
    // Each row: { filePath, enabled, sourceExt, targetExt,
    //             outputName, ovVideoCodec, ovAudioCodec, ovCrf }
    ListModel { id: batchModel }
    property string overrideExt: ""   // if set, all enabled rows use this ext

    // -- Folder mode state -----------------------------------------------------
    property string folderPath:    ""
    property var    folderFiles:   []
    property string folderOutDir:  ""
    property bool   folderSameDir: true
    property bool   folderRecurse: true

    // Folder format rules: [{fromExt, toExt}] + a default catch-all
    ListModel { id: formatRulesModel }
    property string folderDefaultExt: ""

    // -- Results model (shared batch + folder) ---------------------------------
    ListModel { id: batchResults }

    Connections {
        target: bridge
        function onBatchFileCompleted(done, total, filename, success, detail) {
            batchResults.append({ filename: filename, success: success, detail: detail })
            if (batchList.count > 0) batchList.positionViewAtEnd()
        }
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
                            outputName: "", ovVideoCodec: "", ovAudioCodec: "", ovCrf: -1 })
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
            if (item.outputName !== "")    spec.outputName  = item.outputName
            if (item.ovVideoCodec !== "")  spec.videoCodec  = item.ovVideoCodec
            if (item.ovAudioCodec !== "")  spec.audioCodec  = item.ovAudioCodec
            if (item.ovCrf >= 0)           spec.crf         = item.ovCrf
            specs.push(spec)
        }
        return specs
    }

    // Resolve target ext for a folder file using rules then default
    function resolveTargetForFolder(filePath) {
        var src = bridge.detectFormat(filePath)
        for (var i = 0; i < formatRulesModel.count; i++) {
            if (formatRulesModel.get(i).fromExt === src)
                return formatRulesModel.get(i).toExt
        }
        return panel.folderDefaultExt
    }

    // Build folder job specs (each file gets a resolved target)
    function buildFolderJobSpecs() {
        var specs = []
        for (var i = 0; i < folderFiles.length; i++) {
            var tgt = resolveTargetForFolder(folderFiles[i])
            if (tgt === "") continue
            specs.push({ path: folderFiles[i], ext: tgt })
        }
        return specs
    }

    // Unique source extensions present in the folder
    function sourcesInFolder() {
        var seen = {}, result = []
        for (var i = 0; i < folderFiles.length; i++) {
            var ext = bridge.detectFormat(folderFiles[i])
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
        var seen = {}, result = []
        for (var i = 0; i < batchModel.count; i++) {
            var fmts = bridge.formatsFor(batchModel.get(i).filePath)
            for (var j = 0; j < fmts.length; j++)
                if (!seen[fmts[j]]) { seen[fmts[j]] = true; result.push(fmts[j]) }
        }
        return result.sort()
    }

    function folderFormats() {
        var seen = {}, result = []
        for (var i = 0; i < folderFiles.length; i++) {
            var fmts = bridge.formatsFor(folderFiles[i])
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
        panel.folderPath        = dir
        panel.folderFiles       = bridge.scanFolder(dir, panel.folderRecurse)
        panel.folderDefaultExt  = ""
        formatRulesModel.clear()
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
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

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
                Layout.preferredHeight: 120
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
                    anchors.centerIn: parent; spacing: 8
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "📂"; font.pixelSize: 30 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "drop files here or click to browse"
                        font.pixelSize: 12; font.family: root.appFont; color: root.textDim
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

                Rectangle {
                    width: clrAllLbl.implicitWidth + 16; height: 28; radius: 7
                    color: clrAllMa.containsMouse ? root.surfaceHi : root.surface
                    border.color: root.border; border.width: 1
                    Text { id: clrAllLbl; anchors.centerIn: parent; text: "clear all"
                        font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                    MouseArea { id: clrAllMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { batchModel.clear(); panel.overrideExt = "" } }
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

                ScrollView {
                    Layout.fillWidth: true; height: 32
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff; clip: true
                    Row {
                        spacing: 5
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
            }

            // File list
            ScrollView {
                visible: batchModel.count > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                clip: true

                ListView {
                    id: fileListView
                    model: batchModel
                    spacing: 4
                    clip: true

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
                                width: tgtChipLbl.implicitWidth + 14; height: 26; radius: 7
                                color: eff !== "" ? (tgtChipMa.containsMouse ? "#3fa0e8" : "#50b4ff")
                                                  : (tgtChipMa.containsMouse ? root.border : root.surfaceHi)
                                border.color: eff !== "" ? "#50b4ff" : root.border; border.width: 1
                                opacity: model.enabled ? 1.0 : 0.4
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text {
                                    id: tgtChipLbl; anchors.centerIn: parent
                                    text: tgtChip.eff !== "" ? ("." + tgtChip.eff) : "pick..."
                                    font.pixelSize: 11; font.family: root.appFont; font.bold: tgtChip.eff !== ""
                                    color: tgtChip.eff !== "" ? "#0e0e0f" : root.textDim
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
                                border.color: {
                                    var item = batchModel.get(index)
                                    var hasOverride = item && (item.outputName !== "" || item.ovVideoCodec !== "" || item.ovAudioCodec !== "" || item.ovCrf >= 0)
                                    return hasOverride ? root.accent : "transparent"
                                }
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { anchors.centerIn: parent; text: "\u2699"
                                    font.pixelSize: 12; color: {
                                        var item = batchModel.get(index)
                                        var hasOverride = item && (item.outputName !== "" || item.ovVideoCodec !== "" || item.ovAudioCodec !== "" || item.ovCrf >= 0)
                                        return hasOverride ? root.accent : root.textDim
                                    }
                                }
                                MouseArea {
                                    id: gearMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: perFilePopup.openFor(index, rowRect)
                                }
                            }

                            // Remove button
                            Rectangle {
                                width: 22; height: 22; radius: 5
                                color: rmRowMa.containsMouse ? root.errorClr : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { anchors.centerIn: parent; text: "x"
                                    font.pixelSize: 9; color: root.textDim }
                                MouseArea {
                                    id: rmRowMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: batchModel.remove(index)
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
            spacing: 12

            Rectangle {
                Layout.fillWidth: true; height: 90; radius: 8
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
                            panel.folderPath       = p
                            panel.folderFiles      = bridge.scanFolder(p, panel.folderRecurse)
                            panel.folderDefaultExt = ""
                            formatRulesModel.clear()
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent; spacing: 6
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                        text: panel.folderPath !== "" ? "📁" : "📂"; font.pixelSize: 28 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: panel.folderPath !== ""
                              ? (panel.folderPath.split("/").pop() || panel.folderPath)
                              : "drop a folder or click to browse"
                        font.pixelSize: 12; font.family: root.appFont
                        color: panel.folderPath !== "" ? root.textPrim : root.textDim
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
                            panel.folderRecurse    = !panel.folderRecurse
                            panel.folderFiles      = bridge.scanFolder(panel.folderPath, panel.folderRecurse)
                            panel.folderDefaultExt = ""
                            formatRulesModel.clear()
                        }
                    }
                }

                Text {
                    text: panel.folderFiles.length === 0 ? "no supported files found"
                          : (panel.folderFiles.length + " file"
                             + (panel.folderFiles.length === 1 ? "" : "s") + " found")
                    font.pixelSize: 11; font.family: root.appFont
                    color: panel.folderFiles.length > 0 ? root.textMid : root.textDim
                }
                Item { Layout.fillWidth: true }
            }

            // -- Format rules editor (when folder has files) ---------------------
            ColumnLayout {
                visible: panel.folderPath !== "" && panel.folderFiles.length > 0
                Layout.fillWidth: true; spacing: 6

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
                            Text { text: "." + model.fromExt + "  \u2192"
                                font.pixelSize: 11; font.family: root.appFont; color: root.textMid }
                            Rectangle {
                                width: ruleTgtLbl.implicitWidth + 14; height: 24; radius: 5
                                color: root.surfaceHi; border.color: root.accent; border.width: 1
                                Text { id: ruleTgtLbl; anchors.centerIn: parent; text: "." + model.toExt
                                    font.pixelSize: 11; font.family: root.appFont; color: root.accent }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 20; height: 20; radius: 4
                                color: rmRuleMa.containsMouse ? root.errorClr : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { anchors.centerIn: parent; text: "x"; font.pixelSize: 9
                                    color: root.textDim }
                                MouseArea { id: rmRuleMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: formatRulesModel.remove(index) }
                            }
                        }
                    }
                }

                // Default (catch-all) row
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: "default:"; font.pixelSize: 10; font.bold: true
                        font.family: root.appFont; color: root.textDim }
                    ScrollView {
                        Layout.fillWidth: true; height: 32
                        ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff; clip: true
                        Row {
                            spacing: 5
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

                // Folder files preview list (first 8 + count)
                Rectangle {
                    Layout.fillWidth: true
                    height: Math.min(folderPreviewList.contentHeight + 12, 160) + 12
                    color: root.surface; radius: 8; border.color: root.border; border.width: 1; clip: true
                    visible: panel.folderFiles.length > 0

                    ListView {
                        id: folderPreviewList
                        anchors.fill: parent; anchors.margins: 6
                        model: Math.min(panel.folderFiles.length, 12)
                        spacing: 3; clip: true

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
                            Text { text: tgt !== "" ? ("\u2192 ." + tgt) : "(skip)"
                                font.pixelSize: 10; font.family: root.appFont
                                color: tgt !== "" ? root.accent : root.textDim }
                        }

                        footer: Item {
                            visible: panel.folderFiles.length > 12
                            height: visible ? 22 : 0
                            Text {
                                anchors.centerIn: parent
                                text: "…and " + (panel.folderFiles.length - 12) + " more"
                                font.pixelSize: 10; font.family: root.appFont; color: root.textDim
                            }
                        }
                    }
                }
            }

            RowLayout {
                visible: panel.folderPath !== ""
                Layout.fillWidth: true; spacing: 8

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

        // -- Advanced options --------------------------------------------------
        AdvancedPanel {
            id: advPanel
            Layout.fillWidth: true
            targetExt: panel.primaryTargetExt()
        }

        Item { height: 4 }

        // -- Convert button ----------------------------------------------------
        Item {
            Layout.fillWidth: true
            height: 44

            property bool canConvert: {
                if (bridge.converting) return false
                if (panel.mode === 0) return panel.enabledCount() > 0
                if (panel.folderPath === "" || panel.folderFiles.length === 0) return false
                // Need at least one file with a resolved target
                for (var i = 0; i < panel.folderFiles.length; i++) {
                    if (panel.resolveTargetForFolder(panel.folderFiles[i]) !== "") return true
                }
                return false
            }

            property string label: {
                if (bridge.converting) return "converting..."
                if (panel.mode === 0) {
                    var n = panel.enabledCount()
                    return n > 0 ? ("convert " + n + " file" + (n === 1 ? "" : "s") + " →") : "convert →"
                }
                // folder mode: count those with resolved targets
                var fn = 0
                for (var i = 0; i < panel.folderFiles.length; i++) {
                    if (panel.resolveTargetForFolder(panel.folderFiles[i]) !== "") fn++
                }
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
        }

        // -- Batch results -----------------------------------------------------
        Rectangle {
            visible: batchResults.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(batchList.contentHeight + 16, 180)
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

        Item { Layout.fillHeight: true }
    }

    // -- Per-file settings popup -----------------------------------------------
    Popup {
        id: perFilePopup
        property int rowIdx: -1
        modal: false
        padding: 14

        background: Rectangle {
            color: root.surfaceHi; radius: 10
            border.color: root.accent; border.width: 1
        }

        function openFor(idx, anchor) {
            rowIdx = idx
            var item = batchModel.get(idx)
            pfNameInput.text        = item.outputName
            pfVideoInput.text       = item.ovVideoCodec
            pfAudioInput.text       = item.ovAudioCodec
            pfCrfInput.text         = item.ovCrf >= 0 ? item.ovCrf.toString() : ""
            var pos = anchor.mapToItem(panel, 0, anchor.height + 4)
            x = Math.min(Math.max(pos.x, 4), panel.width - implicitWidth - 4)
            y = Math.min(pos.y, panel.height - implicitHeight - 4)
            open()
        }

        contentItem: ColumnLayout {
            spacing: 10
            width: 280

            Text { text: perFilePopup.rowIdx >= 0 && perFilePopup.rowIdx < batchModel.count
                        ? batchModel.get(perFilePopup.rowIdx).filePath.split("/").pop().split("\\").pop()
                        : ""
                font.pixelSize: 11; font.bold: true; font.family: root.appFont
                color: root.textPrim; elide: Text.ElideMiddle; Layout.fillWidth: true }

            GridLayout { columns: 2; columnSpacing: 10; rowSpacing: 8
                Text { text: "output name"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: pfNameInput.activeFocus ? root.accent : root.border; border.width: 1
                    TextInput {
                        id: pfNameInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        placeholderText: "keep original"
                        Text { visible: !parent.text.length; anchors.fill: parent; text: parent.placeholderText
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim }
                    }
                }
                Text { text: "video codec"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: pfVideoInput.activeFocus ? root.accent : root.border; border.width: 1
                    TextInput {
                        id: pfVideoInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        placeholderText: "global default"
                        Text { visible: !parent.text.length; anchors.fill: parent; text: parent.placeholderText
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim }
                    }
                }
                Text { text: "audio codec"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 6
                    color: root.surface; border.color: pfAudioInput.activeFocus ? root.accent : root.border; border.width: 1
                    TextInput {
                        id: pfAudioInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        placeholderText: "global default"
                        Text { visible: !parent.text.length; anchors.fill: parent; text: parent.placeholderText
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim }
                    }
                }
                Text { text: "CRF"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                Rectangle {
                    width: 70; height: 28; radius: 6
                    color: root.surface; border.color: pfCrfInput.activeFocus ? root.accent : root.border; border.width: 1
                    TextInput {
                        id: pfCrfInput; anchors.fill: parent; anchors.margins: 6
                        font.pixelSize: 11; font.family: root.appFont; color: root.textPrim
                        validator: IntValidator { bottom: 0; top: 63 }
                        inputMethodHints: Qt.ImhDigitsOnly
                        placeholderText: "global"
                        Text { visible: !parent.text.length; anchors.fill: parent; text: parent.placeholderText
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
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
                            pfNameInput.text = ""; pfVideoInput.text = ""
                            pfAudioInput.text = ""; pfCrfInput.text = ""
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: pfApplyLbl.implicitWidth + 20; height: 30; radius: 7
                    color: pfApplyMa.containsMouse ? root.accentDim : root.accent
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { id: pfApplyLbl; anchors.centerIn: parent; text: "apply"
                        font.pixelSize: 11; font.bold: true; font.family: root.appFont; color: "#0e0e0f" }
                    MouseArea {
                        id: pfApplyMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var idx = perFilePopup.rowIdx
                            if (idx < 0 || idx >= batchModel.count) { perFilePopup.close(); return }
                            batchModel.setProperty(idx, "outputName",   pfNameInput.text)
                            batchModel.setProperty(idx, "ovVideoCodec", pfVideoInput.text)
                            batchModel.setProperty(idx, "ovAudioCodec", pfAudioInput.text)
                            batchModel.setProperty(idx, "ovCrf",        pfCrfInput.text.length > 0 ? parseInt(pfCrfInput.text) : -1)
                            perFilePopup.close()
                        }
                    }
                }
            }
        }
    }

    // -- Add-rule popup --------------------------------------------------------
    Popup {
        id: addRulePopup
        property string fromExt: ""
        modal: true
        padding: 14

        background: Rectangle {
            color: root.surfaceHi; radius: 10
            border.color: root.border; border.width: 1
        }

        function openFor(srcExt, anchor) {
            fromExt = srcExt
            arFromInput.text = srcExt
            arToInput.text   = ""
            if (anchor) {
                var pos = anchor.mapToItem(panel, 0, anchor.height + 4)
                x = Math.min(pos.x, panel.width - implicitWidth - 4)
                y = Math.min(pos.y, panel.height - implicitHeight - 4)
            } else {
                x = panel.width  / 2 - implicitWidth  / 2
                y = panel.height / 2 - implicitHeight / 2
            }
            open()
        }

        contentItem: ColumnLayout {
            spacing: 12
            width: 240

            Text { text: "add format rule"; font.pixelSize: 12; font.bold: true
                font.family: root.appFont; color: root.textPrim }

            RowLayout { spacing: 8
                ColumnLayout { spacing: 4
                    Text { text: "from ext"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                    Rectangle {
                        width: 90; height: 30; radius: 6
                        color: root.surface; border.color: arFromInput.activeFocus ? root.accent : root.border; border.width: 1
                        TextInput {
                            id: arFromInput; anchors.fill: parent; anchors.margins: 6
                            font.pixelSize: 12; font.family: root.appFont; color: root.textPrim
                            placeholderText: "mp4"
                            Text { visible: !parent.text.length; anchors.fill: parent; text: parent.placeholderText
                                font.pixelSize: 12; font.family: root.appFont; color: root.textDim }
                        }
                    }
                }
                Text { text: "\u2192"; font.pixelSize: 18; color: root.textDim; Layout.alignment: Qt.AlignVCenter | Qt.AlignBottom; bottomPadding: 4 }
                ColumnLayout { spacing: 4
                    Text { text: "to ext"; font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                    Rectangle {
                        width: 90; height: 30; radius: 6
                        color: root.surface; border.color: arToInput.activeFocus ? root.accent : root.border; border.width: 1
                        TextInput {
                            id: arToInput; anchors.fill: parent; anchors.margins: 6
                            font.pixelSize: 12; font.family: root.appFont; color: root.textPrim
                            placeholderText: "mp3"
                            Text { visible: !parent.text.length; anchors.fill: parent; text: parent.placeholderText
                                font.pixelSize: 12; font.family: root.appFont; color: root.textDim }
                        }
                    }
                }
            }

            RowLayout { spacing: 8
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
                    width: arAddLbl.implicitWidth + 20; height: 30; radius: 7
                    color: (arFromInput.text.trim() !== "" && arToInput.text.trim() !== "")
                           ? (arAddMa.containsMouse ? root.accentDim : root.accent)
                           : root.border
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { id: arAddLbl; anchors.centerIn: parent; text: "add rule"
                        font.pixelSize: 11; font.bold: true; font.family: root.appFont; color: "#0e0e0f" }
                    MouseArea {
                        id: arAddMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: arFromInput.text.trim() !== "" && arToInput.text.trim() !== ""
                                     ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            var from = arFromInput.text.trim().replace(/^\./, "")
                            var to   = arToInput.text.trim().replace(/^\./, "")
                            if (from === "" || to === "") return
                            // Remove any existing rule for this from ext
                            for (var i = formatRulesModel.count - 1; i >= 0; i--)
                                if (formatRulesModel.get(i).fromExt === from) formatRulesModel.remove(i)
                            formatRulesModel.append({ fromExt: from, toExt: to })
                            addRulePopup.close()
                        }
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
