#pragma once

#include <QObject>
#include <QUrl>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QThread>
#include <QTimer>
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
