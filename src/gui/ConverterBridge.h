#pragma once

#include <QObject>
#include <QUrl>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QThread>
#include <QTimer>
#include <QFileDialog>
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

// ── The main QML-exposed bridge class ────────────────────────────────────────
class ConverterBridge : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool converting READ converting NOTIFY convertingChanged)
    Q_PROPERTY(float progress  READ progress  NOTIFY progressChanged)
    Q_PROPERTY(QString progressMessage READ progressMessage NOTIFY progressChanged)
    Q_PROPERTY(int batchTotal READ batchTotal NOTIFY batchTotalChanged)
    Q_PROPERTY(int batchDone  READ batchDone  NOTIFY batchDoneChanged)

public:
    explicit ConverterBridge(QObject* parent = nullptr) : QObject(parent) {}

    bool    converting()      const { return m_converting; }
    float   progress()        const { return m_progress; }
    QString progressMessage() const { return m_progressMessage; }
    int     batchTotal()      const { return m_batchTotal; }
    int     batchDone()       const { return m_batchDone; }

    // ── Convert a single file ─────────────────────────────────────────────────
    Q_INVOKABLE void convertFile(
        const QString& inputPath,
        const QString& outputPath,
        const QVariantMap& options = {})
    {
        if (m_converting) return;

        m_converting = true;
        m_progress   = 0.0f;
        m_progressMessage = "Starting...";
        emit convertingChanged();
        emit progressChanged();

        ConversionJob job;
        job.inputPath  = fs::path(inputPath.toStdString());
        job.outputPath = fs::path(outputPath.toStdString());

        applyOptions(job, options);

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
            { "Images",    "🖼",  {"png","jpg","webp","bmp","tiff","gif","heic","avif","exr","tga","svg","raw","cr2","nef","arw","dng"} },
            { "Video",     "🎬",  {"mp4","mov","avi","mkv","webm","flv","wmv","ogv","ts","vob"} },
            { "Audio",     "🎵",  {"mp3","wav","flac","aac","ogg","opus","m4a","wma","aiff","caf"} },
            { "3D Models", "🧊",  {"fbx","obj","glb","gltf","stl","dae","ply","3ds","usd","usdz"} },
            { "Archives",  "📦",  {"zip","tar","gz","bz2","xz","7z","rar","zst","tgz","tbz2","txz","lz4","lzma"} },
            { "Data",      "📊",  {"json","xml","yaml","yml","csv","tsv","toml","ini","env"} },
            { "Documents", "📄",  {"pdf","docx","doc","odt","rtf","xlsx","xls","ods","pptx","ppt","odp","txt","html","md","rst","tex"} },
            { "Ebooks",    "📚",  {"epub","mobi","azw3","azw","fb2","djvu","lit"} },
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
            QString name, desc, videoCodec, audioCodec;
            int     crf;           // -1 = not set
            QString audioBitrate;  // "" = not set
        };
        using PL = QList<Preset>;

        static const QHash<QString, PL> table {
            {"mp4", PL{
                {"H.264 · Balanced",    "Best compatibility · good quality",            "libx264",     "aac",       18, ""},
                {"H.264 · Small file",  "Smaller size, slight quality reduction",       "libx264",     "aac",       26, ""},
                {"H.264 NVENC",         "GPU-accelerated H.264 (NVIDIA)",               "h264_nvenc",  "aac",       -1, ""},
                {"H.265 / HEVC",        "~40% smaller than H.264, needs modern player", "libx265",     "aac",       20, ""},
                {"H.265 NVENC",         "GPU-accelerated HEVC (NVIDIA)",                "hevc_nvenc",  "aac",       -1, ""},
                {"AV1",                 "Best compression, very slow encode",           "libaom-av1",  "libopus",   30, ""},
            }},
            {"mkv", PL{
                {"H.264 · Balanced",    "Best compatibility · good quality",            "libx264",     "aac",       18, ""},
                {"H.264 NVENC",         "GPU-accelerated H.264 (NVIDIA)",               "h264_nvenc",  "aac",       -1, ""},
                {"H.265 / HEVC",        "~40% smaller than H.264",                      "libx265",     "aac",       20, ""},
                {"H.265 NVENC",         "GPU-accelerated HEVC (NVIDIA)",                "hevc_nvenc",  "aac",       -1, ""},
                {"AV1",                 "Best compression, very slow encode",           "libaom-av1",  "libopus",   30, ""},
                {"VP9 + Opus",          "Open format, good browser support",            "libvpx-vp9",  "libopus",   20, ""},
            }},
            {"webm", PL{
                {"VP9 · Quality",       "Best quality, wide browser support",           "libvpx-vp9",  "libopus",   20, ""},
                {"VP9 · Fast",          "Faster encode, slightly larger file",          "libvpx-vp9",  "libopus",   30, ""},
                {"VP8 · Compat",        "Older format, maximum compatibility",          "libvpx",      "libvorbis", -1, ""},
                {"AV1",                 "Best compression, very slow encode",           "libaom-av1",  "libopus",   30, ""},
            }},
            {"mov", PL{
                {"H.264 · Apple",       "Standard Apple / Final Cut compatible",        "libx264",     "aac",       18, ""},
                {"ProRes 422",          "Near-lossless, large file, pro editing",       "prores_ks",   "pcm_s16le", -1, ""},
            }},
            {"avi", PL{
                {"MPEG-4 · Compat",     "Widest AVI compatibility",                     "mpeg4",       "libmp3lame", -1, "192k"},
            }},
            {"mp3", PL{
                {"MP3 · 192k",          "Good quality, universal compatibility",        "",            "libmp3lame", -1, "192k"},
                {"MP3 · 320k",          "High quality, larger file",                    "",            "libmp3lame", -1, "320k"},
                {"MP3 · 128k",          "Smaller file, adequate quality",               "",            "libmp3lame", -1, "128k"},
            }},
            {"ogg", PL{
                {"Vorbis · Quality",    "VBR ~192k equivalent",                         "",            "libvorbis",  -1, ""},
            }},
            {"opus", PL{
                {"Opus · 128k",         "Excellent quality at low bitrate",             "",            "libopus",    -1, "128k"},
                {"Opus · 64k",          "Very small file, good for voice/calls",        "",            "libopus",    -1, "64k"},
            }},
            {"flac", PL{
                {"FLAC · Lossless",     "Bit-perfect audio, large file",                "",            "flac",       -1, ""},
            }},
            {"wav", PL{
                {"PCM 16-bit",          "Uncompressed, maximum compatibility",          "",            "pcm_s16le",  -1, ""},
                {"PCM 24-bit",          "Uncompressed, higher bit depth",               "",            "pcm_s24le",  -1, ""},
            }},
            {"aac", PL{
                {"AAC · 192k",          "Good quality, native MP4/MOV support",         "",            "aac",        -1, "192k"},
                {"AAC · 256k",          "High quality",                                 "",            "aac",        -1, "256k"},
            }},
            {"gif", PL{
                {"Standard GIF",        "Palette-optimised · full compatibility",       "",            "",           -1, ""},
            }},
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
            m["crf"]          = (p.crf >= 0) ? QVariant(p.crf) : QVariant(QString(""));
            m["audioBitrate"] = p.audioBitrate;
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

        m_converting  = true;
        m_batchTotal  = jobSpecs.size();
        m_batchDone   = 0;
        m_progress    = 0.0f;
        m_progressMessage = QString("0 / %1").arg(m_batchTotal);
        emit convertingChanged();
        emit progressChanged();
        emit batchTotalChanged();
        emit batchDoneChanged();

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
                "videoCodec","audioCodec","videoBitrate","audioBitrate",
                "resolution","framerate","pixelFormat","crf"
            };
            for (const QString& k : overrideKeys) {
                if (spec.contains(k) && !spec.value(k).toString().isEmpty())
                    merged[k] = spec.value(k);
            }
            job.force = forceGlobal || spec.value("force", false).toBool();
            applyOptions(job, merged);
            jobs << std::move(job);
        }

        // Reuse the existing BatchWorker infrastructure
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

    // ── Scan a folder for files with known formats ─────────────────────────────
    Q_INVOKABLE QStringList scanFolder(const QString& dirPath, bool recursive) const {
        auto& reg = FormatRegistry::instance();
        QStringList result;
        fs::path root(dirPath.toStdString());
        if (!fs::exists(root) || !fs::is_directory(root)) return result;

        auto scan = [&](const fs::path& dir, bool recurse, auto& self) -> void {
            for (auto& entry : fs::directory_iterator(dir)) {
                if (entry.is_regular_file()) {
                    if (reg.detect(entry.path()))
                        result << QString::fromStdString(entry.path().string());
                } else if (recurse && entry.is_directory()) {
                    self(entry.path(), recurse, self);
                }
            }
        };
        scan(root, recursive, scan);
        return result;
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

    // ── Batch convert a list of files with per-file target extensions ──────────
    Q_INVOKABLE void convertBatch(
        const QStringList& inputPaths,
        const QStringList& targetExts,
        const QString& outputDir,
        const QVariantMap& options = {})
    {
        if (m_converting || inputPaths.isEmpty()) return;

        m_converting  = true;
        m_batchTotal  = inputPaths.size();
        m_batchDone   = 0;
        m_progress    = 0.0f;
        m_progressMessage = QString("0 / %1").arg(m_batchTotal);
        emit convertingChanged();
        emit progressChanged();
        emit batchTotalChanged();
        emit batchDoneChanged();

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
            jobs << std::move(job);
        }

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

private:
    bool    m_converting      = false;
    float   m_progress        = 0.0f;
    QString m_progressMessage;
    int     m_batchTotal      = 0;
    int     m_batchDone       = 0;

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
        job.audioBitrate = getStr("audioBitrate");
        job.resolution   = getStr("resolution");
        job.framerate    = getStr("framerate");
        job.pixelFormat  = getStr("pixelFormat");
        if (opts.contains("force")) job.force = opts.value("force").toBool();

        if (opts.contains("crf")) {
            bool ok;
            int crf = opts.value("crf").toInt(&ok);
            if (ok) job.crf = crf;
        }
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
