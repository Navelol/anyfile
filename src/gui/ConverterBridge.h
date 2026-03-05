#pragma once

#include <QObject>
#include <QUrl>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <QThread>
#include <QTimer>
#include <QFileDialog>
#include <QDesktopServices>
#include <QtQml/qqml.h>

#include "../core/Dispatcher.h"
#include "../core/FormatRegistry.h"

namespace converter {

// ── Worker thread for async conversion ───────────────────────────────────────
class ConversionWorker : public QObject {
    Q_OBJECT
public:
    ConversionJob job;

public slots:
    void run() {
        auto result = Dispatcher::dispatch(job);
        emit finished(result);
    }

signals:
    void finished(converter::ConversionResult result);
};

// ── Worker thread for batch conversion ───────────────────────────────────────
class BatchWorker : public QObject {
    Q_OBJECT
public:
    QList<ConversionJob> jobs;

public slots:
    void run() {
        const int total = jobs.size();
        int succeeded = 0;
        double totalSecs = 0.0;

        for (int i = 0; i < total; ++i) {
            emit fileStarted(i, total,
                QString::fromStdString(jobs[i].inputPath.filename().string()));

            // Skip if output exists and force is not set
            if (!jobs[i].force && fs::exists(jobs[i].outputPath)) {
                emit fileCompleted(i + 1, total,
                    QString::fromStdString(jobs[i].inputPath.filename().string()),
                    false, "file exists (use force overwrite to replace)");
                continue;
            }

            auto result = Dispatcher::dispatch(jobs[i]);

            if (result.success) {
                ++succeeded;
                totalSecs += result.durationSeconds;
                emit fileCompleted(i + 1, total,
                    QString::fromStdString(jobs[i].inputPath.filename().string()),
                    true,
                    QString::fromStdString(result.outputPath.string()));
            } else {
                emit fileCompleted(i + 1, total,
                    QString::fromStdString(jobs[i].inputPath.filename().string()),
                    false,
                    QString::fromStdString(result.errorMsg));
            }
        }
        emit finished(succeeded, total - succeeded, totalSecs);
    }

signals:
    void fileStarted(int index, int total, const QString& filename);
    void fileCompleted(int done, int total, const QString& filename,
                       bool success, const QString& detail);
    void finished(int succeeded, int failed, double totalSecs);
};

// ── Worker thread for async folder scanning ──────────────────────────────────
class ScanWorker : public QObject {
    Q_OBJECT
public:
    QString dirPath;
    bool recursive = false;
    int maxFiles = 100000;

public slots:
    void run() {
        auto& reg = FormatRegistry::instance();
        QStringList files;
        QHash<QString, QString>     formatCache;    // filePath → detected ext
        QHash<QString, QStringList> targetsCache;   // filePath → available target exts
        QStringList categories;
        QHash<QString, bool> catSeen;

        fs::path root(dirPath.toStdString());
        if (!fs::exists(root) || !fs::is_directory(root)) {
            emit finished(files, formatCache, targetsCache, categories);
            return;
        }

        auto scan = [&](const fs::path& dir, bool recurse, auto& self) -> void {
            if (files.size() >= maxFiles) return;
            std::error_code ec;
            fs::directory_iterator it(dir, ec);
            if (ec) return;
            for (auto& entry : it) {
                if (files.size() >= maxFiles) return;
                try {
                    if (entry.is_regular_file(ec) && !ec) {
                        auto fmt = reg.detect(entry.path());
                        if (fmt) {
                            QString path = QString::fromStdString(entry.path().string());
                            QString ext  = QString::fromStdString(fmt->ext);
                            files << path;
                            formatCache[path] = ext;

                            // Cache targets
                            auto tgts = reg.targetsFor(fmt->ext);
                            QStringList tgtList;
                            tgtList.reserve((int)tgts.size());
                            for (auto& t : tgts) tgtList << QString::fromStdString(t);
                            targetsCache[path] = tgtList;

                            // Track categories
                            QString cat;
                            switch (fmt->category) {
                                case Category::Image:    cat = "Image";    break;
                                case Category::Video:    cat = "Video";    break;
                                case Category::Audio:    cat = "Audio";    break;
                                case Category::Model3D:  cat = "3D Model"; break;
                                case Category::Document: cat = "Document"; break;
                                case Category::Ebook:    cat = "Ebook";    break;
                                case Category::Archive:  cat = "Archive";  break;
                                case Category::Data:     cat = "Data";     break;
                                default:                 cat = "Unknown";  break;
                            }
                            if (!catSeen.contains(cat)) {
                                catSeen[cat] = true;
                                categories << cat;
                            }
                        }
                    } else if (recurse && entry.is_directory(ec) && !ec) {
                        self(entry.path(), recurse, self);
                    }
                } catch (...) {}
            }
        };
        scan(root, recursive, scan);

        emit finished(files, formatCache, targetsCache, categories);
    }

signals:
    void finished(QStringList files,
                  QHash<QString, QString> formatCache,
                  QHash<QString, QStringList> targetsCache,
                  QStringList categories);
};

// ── The main QML-exposed bridge class ────────────────────────────────────────
class ConverterBridge : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool converting READ converting NOTIFY convertingChanged)
    Q_PROPERTY(float progress  READ progress  NOTIFY progressChanged)
    Q_PROPERTY(QString progressMessage READ progressMessage NOTIFY progressChanged)
    Q_PROPERTY(int batchTotal READ batchTotal NOTIFY batchTotalChanged)
    Q_PROPERTY(int batchDone  READ batchDone  NOTIFY batchDoneChanged)
    Q_PROPERTY(bool scanning  READ scanning   NOTIFY scanningChanged)

public:
    explicit ConverterBridge(QObject* parent = nullptr) : QObject(parent) {}

    bool    converting()      const { return m_converting; }
    float   progress()        const { return m_progress; }
    QString progressMessage() const { return m_progressMessage; }
    int     batchTotal()      const { return m_batchTotal; }
    int     batchDone()       const { return m_batchDone; }
    bool    scanning()        const { return m_scanning; }

    Q_INVOKABLE void cancelConversion() {
        m_cancelFlag.store(true);
    }

    // ── Convert a single file ─────────────────────────────────────────────────
    Q_INVOKABLE void convertFile(
        const QString& inputPath,
        const QString& outputPath,
        const QVariantMap& options = {})
    {
        if (m_converting) return;

        m_cancelFlag.store(false);
        m_converting = true;
        m_progress   = 0.0f;
        m_progressMessage = "Starting...";
        emit convertingChanged();
        emit progressChanged();

        ConversionJob job;
        job.inputPath  = fs::path(inputPath.toStdString());
        job.outputPath = fs::path(outputPath.toStdString());

        applyOptions(job, options);
        job.cancelFlag = &m_cancelFlag;

        // Progress callback — must marshal to main thread
        job.onProgress = [this](float p, const std::string& msg) {
            QMetaObject::invokeMethod(this, [this, p, msg]() {
                m_progress        = p;
                m_progressMessage = QString::fromStdString(msg);
                emit progressChanged();
            }, Qt::QueuedConnection);
        };

        auto* worker = new ConversionWorker();
        auto* thread = new QThread(this);
        worker->job  = std::move(job);
        worker->moveToThread(thread);

        connect(thread, &QThread::started,  worker, &ConversionWorker::run);
        connect(worker, &ConversionWorker::finished, this, [this, worker, thread](ConversionResult res) {
            thread->quit();
            worker->deleteLater();
            thread->deleteLater();
            m_converting = false;
            emit convertingChanged();
            onConversionFinished(res);
        }, Qt::QueuedConnection);

        thread->start();
    }

    // ── Get valid output formats for an input file ────────────────────────────
    Q_INVOKABLE QStringList formatsFor(const QString& inputPath) const {
        auto& reg = FormatRegistry::instance();
        fs::path p(inputPath.toStdString());
        auto fmt = reg.detect(p);
        if (!fmt) return {};

        auto targets = reg.targetsFor(fmt->ext);
        QStringList out;
        out.reserve((int)targets.size());
        for (auto& t : targets)
            out << QString::fromStdString(t);
        return out;
    }

    // ── Detect format from file path ──────────────────────────────────────────
    Q_INVOKABLE QString detectFormat(const QString& filePath) const {
        auto& reg = FormatRegistry::instance();
        auto fmt  = reg.detect(fs::path(filePath.toStdString()));
        if (!fmt) return "";
        return QString::fromStdString(fmt->ext);
    }

    // ── Category of a format ext ──────────────────────────────────────────────
    Q_INVOKABLE QString categoryFor(const QString& ext) const {
        auto& reg = FormatRegistry::instance();
        auto fmt  = reg.detect(fs::path(("file." + ext.toStdString())));
        if (!fmt) return "Unknown";
        switch (fmt->category) {
            case Category::Image:    return "Image";
            case Category::Video:    return "Video";
            case Category::Audio:    return "Audio";
            case Category::Model3D:  return "3D Model";
            case Category::Document: return "Document";
            case Category::Ebook:    return "Ebook";
            case Category::Archive:  return "Archive";
            case Category::Data:     return "Data";
            default:                 return "Unknown";
        }
    }

    // ── All supported formats grouped ─────────────────────────────────────────
    Q_INVOKABLE QVariantList allFormatsGrouped() const {
        struct Group { QString name; QString icon; QStringList exts; };
        QList<Group> groups = {
            { "Images",    "qrc:/icons/image.svg",     {"png","jpg","webp","bmp","tiff","gif","heic","avif","exr","tga","svg","raw","cr2","nef","arw","dng"} },
            { "Video",     "qrc:/icons/video.svg",     {"mp4","mov","avi","mkv","webm","flv","wmv","ogv","ts","vob"} },
            { "Audio",     "qrc:/icons/audio.svg",     {"mp3","wav","flac","aac","ogg","opus","m4a","wma","aiff","caf"} },
            { "3D Models", "qrc:/icons/3D.svg",        {"fbx","obj","glb","gltf","stl","dae","ply","3ds","usd","usdz"} },
            { "Archives",  "qrc:/icons/archive.svg",   {"zip","tar","gz","bz2","xz","7z","rar","zst","tgz","tbz2","txz","lz4","lzma"} },
            { "Data",      "qrc:/icons/Data.svg",      {"json","xml","yaml","yml","csv","tsv","toml","ini","env"} },
            { "Documents", "qrc:/icons/documents.svg", {"pdf","docx","doc","odt","rtf","xlsx","xls","ods","pptx","ppt","odp","txt","html","md","rst","tex"} },
            { "Ebooks",    "qrc:/icons/ebooks.svg",    {"epub","mobi","azw3","azw","fb2","djvu","lit"} },
        };

        QVariantList result;
        for (auto& g : groups) {
            QVariantMap m;
            m["name"] = g.name;
            m["icon"] = g.icon;
            m["exts"] = g.exts;
            result << m;
        }
        return result;
    }
    // ── Native file picker (bypasses portal, reliably supports multi-select) ──
    Q_INVOKABLE QStringList pickFiles(const QString& title = "Select files") const {
        return QFileDialog::getOpenFileNames(nullptr, title);
    }

    Q_INVOKABLE QString pickFolder(const QString& title = "Select folder") const {
        return QFileDialog::getExistingDirectory(nullptr, title);
    }
    // ── Check if a file path already exists on disk ─────────────────────────
    Q_INVOKABLE bool fileExists(const QString& path) const {
        return fs::exists(fs::path(path.toStdString()));
    }

    // ── Strip file:// prefix from URL ─────────────────────────────────────────
    Q_INVOKABLE QString urlToPath(const QString& url) const {
        if (url.startsWith("file://"))
            return QUrl(url).toLocalFile();
        return url;
    }

    // ── Suggest output path based on input and target ext ─────────────────────
    Q_INVOKABLE QString suggestOutputPath(const QString& inputPath, const QString& targetExt) const {
        fs::path p(inputPath.toStdString());
        fs::path out = p.parent_path() / (p.stem().string() + "." + targetExt.toStdString());
        return QString::fromStdString(out.string());
    }

    // ── Codec presets for a given output extension ────────────────────────────
    Q_INVOKABLE QVariantList codecPresetsFor(const QString& outputExt) const {
        struct Preset {
            QString name, desc, videoCodec, audioCodec, rateMode;
            int     crf;           // -1 = not applicable (VBR mode or no rate control)
            QString audioBitrate;
            QString videoBitrate;  // VBR target
            QString videoMaxRate;  // VBR max
        };
        using PL = QList<Preset>;

        // CRF reference (ffmpeg.org wiki + slhck.info research):
        //   H.264:  16 = visually transparent, 20 = high quality, 26 = good/balanced
        //   H.265:  18 ≈ H.264 16 · same quality ~2pts lower number
        //   VP9:    20 = high, 28 = balanced, 36 = smaller  (0-63 scale)
        //   AV1:    18 = high, 26 = balanced  (0-63 scale)
        // VBR: 1080p typical 8–12M target (high), 4–6M (balanced)
        static const QHash<QString, PL> table {
            {"mp4", PL{
                {"H.264 · Balanced",     "CRF 20 · great quality · fast encode",        "libx264",    "aac",      "crf",  20, "320k", "",    ""},
                {"H.264 · High Quality", "CRF 16 · visually transparent · large file",  "libx264",    "aac",      "crf",  16, "320k", "",    ""},
                {"H.264 · Small File",   "CRF 26 · noticeably smaller · good quality",  "libx264",    "aac",      "crf",  26, "192k", "",    ""},
                {"H.264 · VBR 1-pass",   "10M target · 15M max · fast encode",          "libx264",    "aac",      "vbr1", -1, "320k", "10M", "15M"},
                {"H.264 · VBR 2-pass",   "10M target · 15M max · best bitrate accuracy","libx264",    "aac",      "vbr2", -1, "320k", "10M", "15M"},
                {"H.265 · Balanced",     "CRF 20 ≈ H.264 22 · ~40% smaller file",      "libx265",    "aac",      "crf",  20, "320k", "",    ""},
                {"H.265 · High Quality", "CRF 16 · visually transparent · HEVC",        "libx265",    "aac",      "crf",  16, "320k", "",    ""},
                {"H.265 · Small File",   "CRF 26 · excellent compression",              "libx265",    "aac",      "crf",  26, "192k", "",    ""},
                {"H.264 NVENC",          "GPU-accelerated H.264 · NVIDIA only",         "h264_nvenc", "aac",      "crf",  -1, "320k", "",    ""},
                {"H.265 NVENC",          "GPU-accelerated HEVC · NVIDIA only",          "hevc_nvenc", "aac",      "crf",  -1, "320k", "",    ""},
            }},
            {"mkv", PL{
                {"H.264 · Balanced",     "CRF 20 · great quality · wide compat",        "libx264",    "aac",      "crf",  20, "320k", "",    ""},
                {"H.264 · High Quality", "CRF 16 · visually transparent",               "libx264",    "aac",      "crf",  16, "320k", "",    ""},
                {"H.265 · Balanced",     "CRF 20 · ~40% smaller than H.264",            "libx265",    "aac",      "crf",  20, "320k", "",    ""},
                {"VP9 · Balanced",       "CRF 28 · open format · Opus audio",           "libvpx-vp9", "libopus",  "crf",  28, "192k", "",    ""},
                {"VP9 · High Quality",   "CRF 20 · excellent quality",                  "libvpx-vp9", "libopus",  "crf",  20, "192k", "",    ""},
                {"AV1 · High Quality",   "CRF 18 · best compression · slow encode",     "libaom-av1", "libopus",  "crf",  18, "192k", "",    ""},
                {"H.264 · VBR 2-pass",   "10M target · 15M max · best accuracy",        "libx264",    "aac",      "vbr2", -1, "320k", "10M", "15M"},
                {"H.264 NVENC",          "GPU H.264 · NVIDIA only",                     "h264_nvenc", "aac",      "crf",  -1, "320k", "",    ""},
                {"H.265 NVENC",          "GPU HEVC · NVIDIA only",                      "hevc_nvenc", "aac",      "crf",  -1, "320k", "",    ""},
            }},
            {"webm", PL{
                {"VP9 · Balanced",       "CRF 28 · great quality · good browser support","libvpx-vp9", "libopus", "crf",  28, "192k", "",    ""},
                {"VP9 · High Quality",   "CRF 20 · excellent quality",                  "libvpx-vp9", "libopus",  "crf",  20, "192k", "",    ""},
                {"VP9 · Small File",     "CRF 36 · smaller · good for web",             "libvpx-vp9", "libopus",  "crf",  36, "128k", "",    ""},
                {"VP9 · VBR 1-pass",     "6M target · 9M max · for delivery",           "libvpx-vp9", "libopus",  "vbr1", -1, "192k", "6M",  "9M"},
                {"AV1 · High Quality",   "CRF 18 · best compression · very slow",       "libaom-av1", "libopus",  "crf",  18, "192k", "",    ""},
                {"VP8 · Compat",         "Older format · maximum compatibility",         "libvpx",     "libvorbis","crf",  -1, "",     "",    ""},
            }},
            {"mov", PL{
                {"H.264 · Balanced",     "CRF 20 · Final Cut / QuickTime",              "libx264",    "aac",      "crf",  20, "320k", "",    ""},
                {"H.264 · High Quality", "CRF 16 · visually transparent",               "libx264",    "aac",      "crf",  16, "320k", "",    ""},
                {"ProRes 422",           "Near-lossless · pro editing · large file",    "prores_ks",  "pcm_s16le","crf",  -1, "",     "",    ""},
            }},
            {"avi", PL{
                {"MPEG-4 · Compat",      "Widest AVI compatibility",                    "mpeg4",      "libmp3lame","crf", -1, "320k", "",    ""},
            }},
            {"mp3", PL{
                {"MP3 · 320k",           "High quality · best for music",               "", "libmp3lame","crf",  -1, "320k", "",  ""},
                {"MP3 · 192k",           "Good quality · smaller file",                 "", "libmp3lame","crf",  -1, "192k", "",  ""},
                {"MP3 · 128k",           "Smaller file · adequate for voice",           "", "libmp3lame","crf",  -1, "128k", "",  ""},
            }},
            {"ogg",  PL{ {"Vorbis · HQ", "VBR high quality mode",            "", "libvorbis","crf", -1, "",     "", ""} }},
            {"opus", PL{
                {"Opus · 192k",  "High quality · music",      "", "libopus","crf", -1, "192k", "", ""},
                {"Opus · 128k",  "Excellent at low bitrate",  "", "libopus","crf", -1, "128k", "", ""},
                {"Opus · 64k",   "Very small · voice/calls",  "", "libopus","crf", -1, "64k",  "", ""},
            }},
            {"flac", PL{ {"FLAC · Lossless", "Bit-perfect audio",            "", "flac",     "crf", -1, "",     "", ""} }},
            {"wav",  PL{
                {"PCM 24-bit", "Uncompressed · higher dynamic range", "", "pcm_s24le","crf", -1, "",     "", ""},
                {"PCM 16-bit", "Uncompressed · max compat",           "", "pcm_s16le","crf", -1, "",     "", ""},
            }},
            {"aac",  PL{
                {"AAC · 320k", "High quality · best for music",       "", "aac",      "crf", -1, "320k", "", ""},
                {"AAC · 256k", "Very good quality",                   "", "aac",      "crf", -1, "256k", "", ""},
                {"AAC · 192k", "Good quality · smaller file",         "", "aac",      "crf", -1, "192k", "", ""},
            }},
            {"gif",  PL{ {"Standard GIF", "Palette-optimised · full compat", "", "",        "crf", -1, "",     "", ""} }},
        };

        auto it = table.find(outputExt);
        if (it == table.end()) return {};

        QVariantList result;
        for (const auto& p : *it) {
            QVariantMap m;
            m["name"]         = p.name;
            m["desc"]         = p.desc;
            m["videoCodec"]   = p.videoCodec;
            m["audioCodec"]   = p.audioCodec;
            m["rateMode"]     = p.rateMode;
            m["crf"]          = (p.crf >= 0) ? QVariant(p.crf) : QVariant(QString(""));
            m["audioBitrate"] = p.audioBitrate;
            m["videoBitrate"] = p.videoBitrate;
            m["videoMaxRate"] = p.videoMaxRate;
            result << m;
        }
        return result;
    }

    // ── Batch convert with full per-file control ──────────────────────────────
    // jobSpecs: [{path, ext, outputName?, videoCodec?, audioCodec?, crf?,
    //             videoBitrate?, audioBitrate?, resolution?, framerate?}]
    // globalOptions — same shape as convertBatch options; per-job keys override them.
    Q_INVOKABLE void convertBatchDetailed(
        const QVariantList& jobSpecs,
        const QString& outputDir,
        const QVariantMap& globalOptions = {})
    {
        if (m_converting || jobSpecs.isEmpty()) return;

        const bool forceGlobal = globalOptions.value("force", false).toBool();

        QList<ConversionJob> jobs;
        jobs.reserve(jobSpecs.size());

        for (const QVariant& v : jobSpecs) {
            QVariantMap spec = v.toMap();
            const QString inPath  = spec.value("path").toString();
            const QString tgtExt  = spec.value("ext").toString();
            const QString outName = spec.value("outputName").toString();

            ConversionJob job;
            job.inputPath = fs::path(inPath.toStdString());

            fs::path outDir = outputDir.isEmpty()
                ? job.inputPath.parent_path()
                : fs::path(outputDir.toStdString());
            if (!outDir.empty()) fs::create_directories(outDir);

            // Determine output filename
            std::string stem = outName.isEmpty()
                ? job.inputPath.stem().string()
                : outName.toStdString();
            job.outputPath = outDir / (stem + "." + tgtExt.toStdString());

            // Merge: global options first, then per-job overrides win
            QVariantMap merged = globalOptions;
            const QStringList overrideKeys {
                "videoCodec","audioCodec","videoBitrate","videoMaxRate",
                "resolution","framerate","pixelFormat","crf","rateMode"
            };
            for (const QString& k : overrideKeys) {
                if (spec.contains(k) && !spec.value(k).toString().isEmpty())
                    merged[k] = spec.value(k);
            }
            job.force = forceGlobal || spec.value("force", false).toBool();
            applyOptions(job, merged);
            job.cancelFlag = &m_cancelFlag;
            jobs << std::move(job);
        }

        startBatchExecution(std::move(jobs));
    }

    // ── Scan a folder for files with known formats ─────────────────────────────
    // ── Quick estimate of total entries in folder (for warning large scans) ───
    Q_INVOKABLE int estimateFolderSize(const QString& dirPath, bool recursive, int maxCount = 50000) const {
        fs::path root(dirPath.toStdString());
        if (!fs::exists(root) || !fs::is_directory(root)) return 0;
        
        int count = 0;
        auto countItems = [&](const fs::path& dir, bool recurse, auto& self) -> void {
            if (count >= maxCount) return; // early exit
            std::error_code ec;
            fs::directory_iterator it(dir, ec);
            if (ec) return;
            for (auto& entry : it) {
                if (count >= maxCount) return;
                try {
                    std::error_code entryEc;
                    if (entry.is_regular_file(entryEc) && !entryEc) {
                        ++count;
                    } else if (recurse && entry.is_directory(entryEc) && !entryEc) {
                        self(entry.path(), recurse, self);
                    }
                } catch (...) {}
            }
        };
        countItems(root, recursive, countItems);
        return count;
    }

    Q_INVOKABLE QStringList scanFolder(const QString& dirPath, bool recursive, int maxFiles = 100000) const {
        auto& reg = FormatRegistry::instance();
        QStringList result;
        fs::path root(dirPath.toStdString());
        if (!fs::exists(root) || !fs::is_directory(root)) return result;

        auto scan = [&](const fs::path& dir, bool recurse, auto& self) -> void {
            if (result.size() >= maxFiles) return; // safety limit
            std::error_code ec;
            fs::directory_iterator it(dir, ec);
            if (ec) return; // permission denied or inaccessible — skip silently
            for (auto& entry : it) {
                if (result.size() >= maxFiles) return; // check limit per entry
                try {
                    if (entry.is_regular_file(ec) && !ec) {
                        if (reg.detect(entry.path()))
                            result << QString::fromStdString(entry.path().string());
                    } else if (recurse && entry.is_directory(ec) && !ec) {
                        self(entry.path(), recurse, self);
                    }
                } catch (...) {
                    // skip any individual entry that throws (e.g. symlink loops, access errors)
                }
            }
        };
        scan(root, recursive, scan);
        return result;
    }

    // ── Async folder scan — runs in background thread, emits folderScanComplete ─
    Q_INVOKABLE void scanFolderAsync(const QString& dirPath, bool recursive, int maxFiles = 100000) {
        if (m_scanning) return;
        m_scanning = true;
        m_formatCache.clear();
        m_targetsCache.clear();
        emit scanningChanged();

        auto* worker = new ScanWorker();
        auto* thread = new QThread(this);
        worker->dirPath   = dirPath;
        worker->recursive = recursive;
        worker->maxFiles  = maxFiles;
        worker->moveToThread(thread);

        connect(thread, &QThread::started, worker, &ScanWorker::run);
        connect(worker, &ScanWorker::finished, this,
            [this, worker, thread](QStringList files,
                                   QHash<QString, QString> fmtCache,
                                   QHash<QString, QStringList> tgtCache,
                                   QStringList categories) {
                thread->quit();
                worker->deleteLater();
                thread->deleteLater();
                m_formatCache  = std::move(fmtCache);
                m_targetsCache = std::move(tgtCache);
                m_scanning = false;
                emit scanningChanged();
                emit folderScanComplete(files, categories);
            }, Qt::QueuedConnection);

        thread->start();
    }

    // ── Cached format lookups — O(1) from scan cache, fallback to live detect ───
    Q_INVOKABLE QString cachedDetectFormat(const QString& filePath) const {
        auto it = m_formatCache.find(filePath);
        if (it != m_formatCache.end()) return it.value();
        return detectFormat(filePath);
    }

    Q_INVOKABLE QStringList cachedFormatsFor(const QString& filePath) const {
        auto it = m_targetsCache.find(filePath);
        if (it != m_targetsCache.end()) return it.value();
        return formatsFor(filePath);
    }

    // ── Compute folder stats in a single pass (avoids O(N) QML bindings) ────────
    // Returns {convertCount, canConvert} given current rules + default ext.
    Q_INVOKABLE QVariantMap computeFolderStats(
        const QStringList& files,
        const QVariantList& rules,
        const QString& defaultExt) const
    {
        int convertCount = 0;
        for (const QString& fp : files) {
            QString src = cachedDetectFormat(fp);
            QString tgt;
            // Check rules
            for (const QVariant& rv : rules) {
                QVariantMap r = rv.toMap();
                if (r.value("fromExt").toString() == src) {
                    tgt = r.value("toExt").toString();
                    break;
                }
            }
            if (tgt.isEmpty()) tgt = defaultExt;
            if (tgt.isEmpty()) continue;
            // Verify convertibility
            QStringList fmts = cachedFormatsFor(fp);
            if (fmts.contains(tgt)) ++convertCount;
        }
        return {{"convertCount", convertCount},
                {"canConvert",   convertCount > 0}};
    }

    // ── Check which output files would already exist (for overwrite dialog) ────
    Q_INVOKABLE QStringList wouldOverwrite(
        const QStringList& inputPaths,
        const QStringList& targetExts,
        const QString& outputDir) const
    {
        QStringList result;
        for (int i = 0; i < inputPaths.size() && i < targetExts.size(); ++i) {
            fs::path inp(inputPaths[i].toStdString());
            fs::path outDir = outputDir.isEmpty()
                ? inp.parent_path()
                : fs::path(outputDir.toStdString());
            fs::path out = outDir / (inp.stem().string() + "." + targetExts[i].toStdString());
            if (fs::exists(out))
                result << QString::fromStdString(out.string());
        }
        return result;
    }

    // Variant that mirrors convertBatchDetailed and respects per-file outputName
    Q_INVOKABLE QStringList wouldOverwriteDetailed(
        const QVariantList& jobSpecs,
        const QString& outputDir) const
    {
        QStringList result;
        for (const QVariant& v : jobSpecs) {
            QVariantMap spec = v.toMap();
            const QString inPath  = spec.value("path").toString();
            const QString tgtExt  = spec.value("ext").toString();
            const QString outName = spec.value("outputName").toString();
            if (inPath.isEmpty() || tgtExt.isEmpty())
                continue;

            fs::path inp(inPath.toStdString());
            fs::path outDirPath = outputDir.isEmpty()
                ? inp.parent_path()
                : fs::path(outputDir.toStdString());

            std::string stem = outName.isEmpty()
                ? inp.stem().string()
                : outName.toStdString();

            fs::path out = outDirPath / (stem + "." + tgtExt.toStdString());
            if (fs::exists(out))
                result << QString::fromStdString(out.string());
        }
        return result;
    }

    // Open a folder in the OS file manager (Windows, macOS, Linux).
    Q_INVOKABLE void openFolderLocation(const QString& path) const
    {
        if (path.isEmpty())
            return;
        QUrl url = QUrl::fromLocalFile(path);
        QDesktopServices::openUrl(url);
    }

    // ── Batch convert a list of files with per-file target extensions ──────────
    Q_INVOKABLE void convertBatch(
        const QStringList& inputPaths,
        const QStringList& targetExts,
        const QString& outputDir,
        const QVariantMap& options = {})
    {
        if (m_converting || inputPaths.isEmpty()) return;

        const bool forceOverwrite = options.value("force", false).toBool();

        QList<ConversionJob> jobs;
        jobs.reserve(inputPaths.size());
        for (int i = 0; i < inputPaths.size(); ++i) {
            const QString& inPath  = inputPaths[i];
            const QString  tgtExt  = (i < targetExts.size()) ? targetExts[i] : (targetExts.isEmpty() ? "" : targetExts.last());
            ConversionJob job;
            job.inputPath = fs::path(inPath.toStdString());
            fs::path outDir = outputDir.isEmpty()
                ? job.inputPath.parent_path()
                : fs::path(outputDir.toStdString());
            if (!outDir.empty()) fs::create_directories(outDir);
            job.outputPath = outDir / (job.inputPath.stem().string() + "." + tgtExt.toStdString());
            job.force = forceOverwrite;
            applyOptions(job, options);
            job.cancelFlag = &m_cancelFlag;
            jobs << std::move(job);
        }

        startBatchExecution(std::move(jobs));
    }

signals:
    void convertingChanged();
    void progressChanged();
    void conversionSucceeded(const QString& outputPath,
                             double durationSeconds,
                             qint64 inputBytes,
                             qint64 outputBytes,
                             const QStringList& warnings);
    void conversionFailed(const QString& errorMessage);
    void batchTotalChanged();
    void batchDoneChanged();
    void batchFileCompleted(int done, int total, const QString& filename,
                            bool success, const QString& detail);
    void batchFinished(int succeeded, int failed, double totalSecs);
    void scanningChanged();
    void folderScanComplete(QStringList files, QStringList categories);

private:
    bool    m_converting      = false;
    float   m_progress        = 0.0f;
    QString m_progressMessage;
    int     m_batchTotal      = 0;
    int     m_batchDone       = 0;
    bool    m_scanning        = false;
    std::atomic<bool> m_cancelFlag { false };
    QHash<QString, QString>     m_formatCache;   // filePath → detected ext
    QHash<QString, QStringList> m_targetsCache;  // filePath → available targets

    void applyOptions(ConversionJob& job, const QVariantMap& opts) {
        auto getStr = [&](const QString& key) -> std::optional<std::string> {
            if (opts.contains(key)) {
                QString v = opts.value(key).toString();
                if (!v.isEmpty()) return v.toStdString();
            }
            return std::nullopt;
        };

        job.videoCodec   = getStr("videoCodec");
        job.audioCodec   = getStr("audioCodec");
        job.videoBitrate = getStr("videoBitrate");
        job.videoMaxRate = getStr("videoMaxRate");
        job.audioBitrate = getStr("audioBitrate");
        job.resolution   = getStr("resolution");
        job.framerate    = getStr("framerate");
        job.pixelFormat  = getStr("pixelFormat");
        if (opts.contains("force")) job.force = opts.value("force").toBool();

        // rateMode: "crf" (default), "vbr1" (1-pass VBR), "vbr2" (2-pass VBR)
        if (opts.contains("rateMode")) {
            QString rm = opts.value("rateMode").toString();
            if (rm == "vbr1") job.twoPass = false;
            if (rm == "vbr2") job.twoPass = true;
            // "crf" → leave twoPass false, CRF is set below
        }

        if (opts.contains("crf")) {
            bool ok;
            int crf = opts.value("crf").toInt(&ok);
            if (ok) job.crf = crf;
        }
    }

    void startBatchExecution(QList<ConversionJob>&& jobs) {
        m_cancelFlag.store(false);
        m_converting  = true;
        m_batchTotal  = jobs.size();
        m_batchDone   = 0;
        m_progress    = 0.0f;
        m_progressMessage = QString("0 / %1").arg(m_batchTotal);
        emit convertingChanged();
        emit progressChanged();
        emit batchTotalChanged();
        emit batchDoneChanged();

        auto* worker = new BatchWorker();
        auto* thread = new QThread(this);
        worker->jobs = std::move(jobs);
        worker->moveToThread(thread);

        connect(thread, &QThread::started, worker, &BatchWorker::run);

        connect(worker, &BatchWorker::fileStarted, this,
            [this](int index, int total, const QString& filename) {
                m_progressMessage = QString("%1 / %2  —  %3").arg(index + 1).arg(total).arg(filename);
                m_progress = (float)index / total;
                emit progressChanged();
            }, Qt::QueuedConnection);

        connect(worker, &BatchWorker::fileCompleted, this,
            [this](int done, int total, const QString& filename, bool success, const QString& detail) {
                m_batchDone = done;
                m_progress  = (float)done / total;
                m_progressMessage = QString("%1 / %2  —  %3").arg(done).arg(total).arg(filename);
                emit batchDoneChanged();
                emit progressChanged();
                emit batchFileCompleted(done, total, filename, success, detail);
            }, Qt::QueuedConnection);

        connect(worker, &BatchWorker::finished, this,
            [this, worker, thread](int succeeded, int failed, double totalSecs) {
                thread->quit();
                worker->deleteLater();
                thread->deleteLater();
                m_converting = false;
                m_progress   = 1.0f;
                m_progressMessage = QString("Done — %1 succeeded, %2 failed").arg(succeeded).arg(failed);
                emit convertingChanged();
                emit progressChanged();
                emit batchFinished(succeeded, failed, totalSecs);
            }, Qt::QueuedConnection);

        thread->start();
    }

    void onConversionFinished(const ConversionResult& res) {
        m_progress        = 1.0f;
        m_progressMessage = res.success ? "Done" : res.errorMsg.c_str();
        emit progressChanged();

        if (res.success) {
            QStringList warnings;
            for (auto& w : res.warnings)
                warnings << QString::fromStdString(w);
            emit conversionSucceeded(
                QString::fromStdString(res.outputPath.string()),
                res.durationSeconds,
                (qint64)res.inputBytes,
                (qint64)res.outputBytes,
                warnings
            );
        } else {
            emit conversionFailed(QString::fromStdString(res.errorMsg));
        }
    }
};

} // namespace converter