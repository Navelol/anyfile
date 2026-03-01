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

// ── The main QML-exposed bridge class ────────────────────────────────────────
class ConverterBridge : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool converting READ converting NOTIFY convertingChanged)
    Q_PROPERTY(float progress  READ progress  NOTIFY progressChanged)
    Q_PROPERTY(QString progressMessage READ progressMessage NOTIFY progressChanged)

public:
    explicit ConverterBridge(QObject* parent = nullptr) : QObject(parent) {}

    bool    converting()      const { return m_converting; }
    float   progress()        const { return m_progress; }
    QString progressMessage() const { return m_progressMessage; }

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

signals:
    void convertingChanged();
    void progressChanged();
    void conversionSucceeded(const QString& outputPath,
                             double durationSeconds,
                             qint64 inputBytes,
                             qint64 outputBytes,
                             const QStringList& warnings);
    void conversionFailed(const QString& errorMessage);

private:
    bool    m_converting      = false;
    float   m_progress        = 0.0f;
    QString m_progressMessage;

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
