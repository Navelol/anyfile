import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: panel

    // ── Exposed mode so Main.qml can hide ResultPanel in batch/folder modes ───
    property int mode: 0  // 0 = single, 1 = batch, 2 = folder

    // ── Single mode state ─────────────────────────────────────────────────────
    property string singleInput:   ""
    property string singleOutput:  ""
    property string singleInExt:   ""
    property string singleOutExt:  ""
    property var    singleFormats: []

    // ── Batch mode state ──────────────────────────────────────────────────────
    property var    batchFiles:   []
    property string batchOutExt:  ""
    property string batchOutDir:  ""
    property bool   batchSameDir: true

    // ── Folder mode state ─────────────────────────────────────────────────────
    property string folderPath:    ""
    property var    folderFiles:   []
    property string folderOutExt:  ""
    property string folderOutDir:  ""
    property bool   folderSameDir: true
    property bool   folderRecurse: true

    // ── Batch results (shared between batch + folder modes) ───────────────────
    ListModel { id: batchResults }

    Connections {
        target: bridge
        function onBatchFileCompleted(done, total, filename, success, detail) {
            batchResults.append({ "filename": filename, "success": success, "detail": detail })
            if (batchList.count > 0) batchList.positionViewAtEnd()
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function batchFormats() {
        var seen = {}, result = []
        for (var i = 0; i < batchFiles.length; i++) {
            var fmts = bridge.formatsFor(batchFiles[i])
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

    function setInputFile(path) {
        singleInput   = path
        singleInExt   = bridge.detectFormat(path)
        singleFormats = bridge.formatsFor(path)
        singleOutExt  = singleFormats.length > 0 ? singleFormats[0] : ""
        singleOutput  = singleOutExt.length > 0
            ? bridge.suggestOutputPath(path, singleOutExt) : ""
        resultPanel.hide()
    }

    function doConvert() {
        if (bridge.converting) return
        if (mode === 0) {
            if (!singleInput || !singleOutput) return
            bridge.convertFile(singleInput, singleOutput, buildOptions())
        } else if (mode === 1) {
            if (batchFiles.length === 0 || !batchOutExt) return
            batchResults.clear()
            bridge.convertBatch(batchFiles, batchOutExt,
                                batchSameDir ? "" : batchOutDir, buildOptions())
        } else {
            if (!folderPath || !folderOutExt || folderFiles.length === 0) return
            batchResults.clear()
            bridge.convertBatch(folderFiles, folderOutExt,
                                folderSameDir ? "" : folderOutDir, buildOptions())
        }
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
        return opts
    }

    // ── Dialogs ───────────────────────────────────────────────────────────────
    FileDialog {
        id: singleInputPicker
        title: "Select input file"
        fileMode: FileDialog.OpenFile
        onAccepted: panel.setInputFile(bridge.urlToPath(selectedFile.toString()))
    }

    FileDialog {
        id: singleOutputPicker
        title: "Save as"
        fileMode: FileDialog.SaveFile
        defaultSuffix: panel.singleOutExt
        onAccepted: {
            var path  = bridge.urlToPath(selectedFile.toString())
            var slash = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
            var dot   = path.lastIndexOf(".")
            if (dot > slash) path = path.substring(0, dot)
            panel.singleOutput = path + "." + panel.singleOutExt
        }
    }

    FileDialog {
        id: batchInputPicker
        title: "Select files"
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            var arr = panel.batchFiles.slice()
            for (var i = 0; i < selectedFiles.length; i++) {
                var p = bridge.urlToPath(selectedFiles[i].toString())
                if (arr.indexOf(p) < 0) arr.push(p)
            }
            panel.batchFiles  = arr
            panel.batchOutExt = ""
        }
    }

    FolderDialog {
        id: batchOutDirPicker
        title: "Choose output folder"
        onAccepted: panel.batchOutDir = bridge.urlToPath(selectedFolder.toString())
    }

    FolderDialog {
        id: folderInputPicker
        title: "Select folder to convert"
        onAccepted: {
            panel.folderPath  = bridge.urlToPath(selectedFolder.toString())
            panel.folderFiles = bridge.scanFolder(panel.folderPath, panel.folderRecurse)
            panel.folderOutExt = ""
        }
    }

    FolderDialog {
        id: folderOutDirPicker
        title: "Choose output folder"
        onAccepted: panel.folderOutDir = bridge.urlToPath(selectedFolder.toString())
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // ── Mode tabs ─────────────────────────────────────────────────────────
        Row {
            spacing: 6
            Repeater {
                model: ["single file", "batch", "folder"]
                delegate: Rectangle {
                    width: tabLbl.implicitWidth + 22
                    height: 30
                    radius: 8
                    color: panel.mode === index
                           ? root.accent
                           : (tabMa.containsMouse ? root.border : root.surface)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        id: tabLbl
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: 11
                        font.bold: true
                        font.family: root.appFont
                        color: panel.mode === index ? "#0e0e0f" : root.textMid
                    }
                    MouseArea {
                        id: tabMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { panel.mode = index; batchResults.clear() }
                    }
                }
            }
        }

        // ── Single mode ───────────────────────────────────────────────────────
        RowLayout {
            visible: panel.mode === 0
            Layout.fillWidth: true
            spacing: 16

            DropZone {
                id: inputZone
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                hasFile: panel.singleInput !== ""
                fileName: panel.singleInput !== ""
                          ? panel.singleInput.split("/").pop().split("\\").pop() : ""
                formatExt: panel.singleInExt
                label: "input"
                placeholderIcon: "📂"
                placeholderText: "drop file here or click to browse"
                onClicked: singleInputPicker.open()
            }

            Column {
                spacing: 6
                Layout.preferredWidth: 48
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "→"
                    font.pixelSize: 28
                    color: panel.singleInput !== "" ? root.accent : root.border
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "to"
                    font.pixelSize: 9
                    font.family: root.appFont
                    font.letterSpacing: 2
                    color: root.textDim
                }
            }

            OutputZone {
                id: outputZone
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                outputPath: panel.singleOutput
                formats: panel.singleFormats
                selectedFormat: panel.singleOutExt
                enabled: panel.singleInput !== ""
                onFormatSelected: function(fmt) {
                    panel.singleOutExt = fmt
                    panel.singleOutput = bridge.suggestOutputPath(panel.singleInput, fmt)
                }
                onBrowseClicked: {
                    if (panel.singleOutExt !== "") singleOutputPicker.open()
                }
            }
        }

        // ── Batch mode ────────────────────────────────────────────────────────
        RowLayout {
            visible: panel.mode === 1
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            spacing: 16

            Rectangle {
                Layout.fillHeight: true
                Layout.fillWidth: true
                color: root.surface
                radius: 8
                border.color: root.border
                border.width: 1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: panel.batchFiles.length === 0
                                  ? "no files selected"
                                  : (panel.batchFiles.length + " file"
                                     + (panel.batchFiles.length === 1 ? "" : "s"))
                            font.pixelSize: 11; font.family: root.appFont; color: root.textDim
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: addLbl.implicitWidth + 16; height: 24; radius: 6
                            color: addMa.containsMouse ? root.accentDim : root.accent
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text { id: addLbl; anchors.centerIn: parent; text: "+ add files"
                                   font.pixelSize: 10; font.bold: true; font.family: root.appFont; color: "#0e0e0f" }
                            MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor; onClicked: batchInputPicker.open() }
                        }
                        Item { width: 4 }
                        Rectangle {
                            visible: panel.batchFiles.length > 0
                            width: clrLbl.implicitWidth + 16; height: 24; radius: 6
                            color: clrMa.containsMouse ? root.surfaceHi : root.surface
                            border.color: root.border; border.width: 1
                            Text { id: clrLbl; anchors.centerIn: parent; text: "clear"
                                   font.pixelSize: 10; font.family: root.appFont; color: root.textDim }
                            MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { panel.batchFiles = []; panel.batchOutExt = "" } }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        clip: true
                        ListView {
                            model: panel.batchFiles
                            spacing: 3
                            delegate: Item {
                                width: ListView.view.width
                                height: 26
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.split("/").pop().split("\\").pop()
                                        font.pixelSize: 11; font.family: root.appFont
                                        color: root.textMid; elide: Text.ElideMiddle
                                    }
                                    Rectangle {
                                        width: 20; height: 20; radius: 4
                                        color: rmMa.containsMouse ? root.errorClr : "transparent"
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 9; color: root.textDim }
                                        MouseArea {
                                            id: rmMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var arr = panel.batchFiles.slice()
                                                arr.splice(index, 1)
                                                panel.batchFiles = arr
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Target format + output dir
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: 230
                spacing: 10

                Text { text: "convert to"; font.pixelSize: 10; font.bold: true
                       font.family: root.appFont; color: root.textDim }

                Item {
                    Layout.fillWidth: true; height: 80
                    Text {
                        visible: panel.batchFiles.length === 0
                        anchors.centerIn: parent; text: "add files first"
                        font.pixelSize: 11; font.family: root.appFont; color: root.textDim
                    }
                    ScrollView {
                        anchors.fill: parent
                        visible: panel.batchFiles.length > 0
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded; clip: true
                        Flow {
                            width: 230; spacing: 5
                            Repeater {
                                model: panel.batchFormats()
                                Rectangle {
                                    width: bfTxt.implicitWidth + 14; height: 26; radius: 7
                                    color: panel.batchOutExt === modelData
                                           ? root.accent : (bfMa.containsMouse ? root.border : root.surface)
                                    border.color: panel.batchOutExt === modelData ? root.accent : root.border; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                    Text { id: bfTxt; anchors.centerIn: parent; text: "." + modelData
                                           font.pixelSize: 11; font.family: root.appFont
                                           font.bold: panel.batchOutExt === modelData
                                           color: panel.batchOutExt === modelData ? "#0e0e0f" : root.textMid }
                                    MouseArea { id: bfMa; anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor; onClicked: panel.batchOutExt = modelData }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: root.border; opacity: 0.5 }
                Text { text: "output folder"; font.pixelSize: 10; font.bold: true
                       font.family: root.appFont; color: root.textDim }

                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 7
                    color: bsaMa.containsMouse ? root.border : root.surface
                    border.color: panel.batchSameDir ? root.accent : root.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "· same as source"
                           font.pixelSize: 11; font.family: root.appFont
                           color: panel.batchSameDir ? root.accent : root.textMid }
                    MouseArea { id: bsaMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: panel.batchSameDir = true }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 7
                    color: bcuMa.containsMouse ? root.border : root.surface
                    border.color: !panel.batchSameDir ? root.accent : root.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: panel.batchOutDir !== ""
                              ? ("📁 " + panel.batchOutDir.split("/").pop())
                              : "· choose folder..."
                        font.pixelSize: 11; font.family: root.appFont
                        color: !panel.batchSameDir ? root.accent : root.textMid; elide: Text.ElideLeft
                    }
                    MouseArea { id: bcuMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { panel.batchSameDir = false; batchOutDirPicker.open() } }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ── Folder mode ───────────────────────────────────────────────────────
        ColumnLayout {
            visible: panel.mode === 2
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true; height: 90; radius: 8
                color: fzMa.containsMouse ? root.surfaceHi : root.surface
                border.color: panel.folderPath !== "" ? root.accent
                              : (fzMa.containsMouse ? root.textDim : root.border)
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }
                clip: true

                DropArea {
                    anchors.fill: parent
                    onDropped: function(drop) {
                        if (drop.urls.length > 0) {
                            var p = bridge.urlToPath(drop.urls[0].toString())
                            panel.folderPath   = p
                            panel.folderFiles  = bridge.scanFolder(p, panel.folderRecurse)
                            panel.folderOutExt = ""
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent; spacing: 6
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                           text: panel.folderPath !== "" ? "📁" : "📂"; font.pixelSize: 28 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                           text: panel.folderPath !== ""
                                 ? (panel.folderPath.split("/").pop() || panel.folderPath)
                                 : "drop a folder or click to browse"
                           font.pixelSize: 12; font.family: root.appFont
                           color: panel.folderPath !== "" ? root.textPrim : root.textDim }
                }

                MouseArea { id: fzMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: folderInputPicker.open() }
            }

            RowLayout {
                visible: panel.folderPath !== ""
                Layout.fillWidth: true; spacing: 10

                Rectangle {
                    width: recLbl.implicitWidth + 24; height: 28; radius: 7
                    color: panel.folderRecurse ? root.accent : root.surface
                    border.color: panel.folderRecurse ? root.accent : root.border; border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { id: recLbl; anchors.centerIn: parent; text: "recursive"
                           font.pixelSize: 11; font.family: root.appFont
                           color: panel.folderRecurse ? "#0e0e0f" : root.textMid }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            panel.folderRecurse = !panel.folderRecurse
                            panel.folderFiles   = bridge.scanFolder(panel.folderPath, panel.folderRecurse)
                            panel.folderOutExt  = ""
                        }
                    }
                }

                Text {
                    text: panel.folderFiles.length === 0
                          ? "no supported files found"
                          : (panel.folderFiles.length + " file"
                             + (panel.folderFiles.length === 1 ? "" : "s") + " found")
                    font.pixelSize: 11; font.family: root.appFont
                    color: panel.folderFiles.length > 0 ? root.textMid : root.textDim
                }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                visible: panel.folderPath !== "" && panel.folderFiles.length > 0
                Layout.fillWidth: true; spacing: 12

                Text { text: "convert to"; font.pixelSize: 10; font.bold: true
                       font.family: root.appFont; color: root.textDim; Layout.alignment: Qt.AlignVCenter }

                ScrollView {
                    Layout.fillWidth: true; height: 36
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff; clip: true
                    Row {
                        spacing: 5
                        Repeater {
                            model: panel.folderFormats()
                            Rectangle {
                                width: ffTxt.implicitWidth + 14; height: 28; radius: 7
                                color: panel.folderOutExt === modelData
                                       ? root.accent : (ffMa.containsMouse ? root.border : root.surface)
                                border.color: panel.folderOutExt === modelData ? root.accent : root.border; border.width: 1
                                Behavior on color { ColorAnimation { duration: 80 } }
                                Text { id: ffTxt; anchors.centerIn: parent; text: "." + modelData
                                       font.pixelSize: 11; font.family: root.appFont
                                       font.bold: panel.folderOutExt === modelData
                                       color: panel.folderOutExt === modelData ? "#0e0e0f" : root.textMid }
                                MouseArea { id: ffMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor; onClicked: panel.folderOutExt = modelData }
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
                                onClicked: { panel.folderSameDir = false; folderOutDirPicker.open() } }
                }
            }
        }

        // ── Advanced options ──────────────────────────────────────────────────
        AdvancedPanel {
            id: advPanel
            Layout.fillWidth: true
            visible: mode === 0 ? panel.singleInput !== "" : true
        }

        Item { height: 4 }

        // ── Convert button ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            height: 44

            property bool canConvert: {
                if (bridge.converting) return false
                if (panel.mode === 0) return panel.singleInput !== "" && panel.singleOutput !== ""
                if (panel.mode === 1) return panel.batchFiles.length > 0 && panel.batchOutExt !== ""
                return panel.folderPath !== "" && panel.folderOutExt !== "" && panel.folderFiles.length > 0
            }

            property string label: {
                if (bridge.converting) return "converting..."
                if (panel.mode === 0) return "convert →"
                var n = panel.mode === 1 ? panel.batchFiles.length : panel.folderFiles.length
                return n > 0 ? ("convert " + n + " file" + (n === 1 ? "" : "s") + " →") : "convert →"
            }

            Rectangle {
                id: convertBtn
                anchors.left: parent.left
                width: Math.max(cvtLbl.implicitWidth + 32, 160)
                height: parent.height
                radius: 8
                color: {
                    if (!parent.canConvert) return root.border
                    if (cvtMa.containsMouse) return root.accentDim
                    return root.accent
                }
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    id: cvtLbl
                    anchors.centerIn: parent
                    text: parent.parent.label
                    font.pixelSize: 13; font.bold: true; font.family: root.appFont
                    color: parent.parent.canConvert ? "#0e0e0f" : root.textDim
                }

                MouseArea {
                    id: cvtMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: parent.parent.canConvert ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (parent.parent.canConvert) panel.doConvert()
                }
            }

            Text {
                visible: panel.mode === 0
                anchors.left: convertBtn.right; anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - convertBtn.width - 14
                text: panel.singleOutput
                font.pixelSize: 11; font.family: root.appFont; color: root.textDim; elide: Text.ElideLeft
            }
        }

        // ── Batch / folder results ────────────────────────────────────────────
        Rectangle {
            visible: panel.mode !== 0 && batchResults.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(batchList.contentHeight + 16, 200)
            color: root.surface; radius: 8; border.color: root.border; border.width: 1; clip: true

            ListView {
                id: batchList
                anchors.fill: parent; anchors.margins: 8; spacing: 3
                model: batchResults; clip: true

                delegate: RowLayout {
                    width: batchList.width; spacing: 8
                    Text { text: model.success ? "✓" : "✗"; font.pixelSize: 11; font.family: root.appFont
                           color: model.success ? root.success : root.errorClr }
                    Text { text: model.filename; font.pixelSize: 11; font.family: root.appFont
                           color: root.textPrim; elide: Text.ElideMiddle; Layout.preferredWidth: 180 }
                    Text { text: model.success ? ("→ " + model.detail.split("/").pop()) : model.detail
                           font.pixelSize: 10; font.family: root.appFont
                           color: model.success ? root.textDim : root.errorClr
                           elide: Text.ElideLeft; Layout.fillWidth: true }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}

