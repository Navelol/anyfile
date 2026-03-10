#pragma once

#include "Types.h"
#include "FormatRegistry.h"
#include "MediaConverter.h"
#include "ModelConverter.h"
#include "DataConverter.h"
#include "DocumentConverter.h"
#include "ArchiveConverter.h"
#include "PdfRenderer.h"
#include "PathValidator.h"
#include <random>

#ifdef __linux__
#  include <fcntl.h>    // fallocate
#  include <unistd.h>
#endif

namespace converter {

class Dispatcher {
public:

    // Main entry point — takes a job and routes it to the right converter
    static ConversionResult dispatch(ConversionJob job) {

        // ── Security: validate paths and options before touching anything ──────
        if (auto err = PathValidator::validateInput(job.inputPath);  !err.empty())
            return ConversionResult::err("Invalid input path: "  + err);
        if (auto err = PathValidator::validateOutput(job.outputPath); !err.empty())
            return ConversionResult::err("Invalid output path: " + err);
        if (auto err = validateJobOptions(job); !err.empty())
            return ConversionResult::err(err);

        // Validate input file exists
        if (!fs::exists(job.inputPath))
            return ConversionResult::err("Input file not found: " + job.inputPath.string());

        // Detect formats if not already set
        auto& reg = FormatRegistry::instance();

        auto inFmt = reg.detect(job.inputPath);
        if (!inFmt)
            return ConversionResult::err("Unknown input format: " + job.inputPath.extension().string());

        auto outFmt = reg.detectByExtension(job.outputPath);
        if (!outFmt)
            return ConversionResult::err("Unknown output format: " + job.outputPath.extension().string());

        job.inputFormat  = *inFmt;
        job.outputFormat = *outFmt;

        // Same format — allow re-encode for media types
        if (inFmt->ext == outFmt->ext) {
            if (inFmt->category == Category::Audio ||
                inFmt->category == Category::Video ||
                inFmt->category == Category::Image) {
                return dispatchAtomic(job);
            }
            return ConversionResult::err("Input and output are the same format");
        }

        // Check the conversion is supported
        if (!reg.canConvert(inFmt->ext, outFmt->ext)) {
            return ConversionResult::err(
                "Conversion from ." + inFmt->ext + " to ." + outFmt->ext + " is not supported"
            );
        }

        // Ensure output directory exists
        auto outDir = job.outputPath.parent_path();
        if (!outDir.empty()) fs::create_directories(outDir);

        return dispatchAtomic(job);
    }

    // Convenience overload
    static ConversionResult dispatch(
        fs::path input,
        fs::path output,
        ProgressFn onProgress = nullptr)
    {
        ConversionJob job;
        job.inputPath  = std::move(input);
        job.outputPath = std::move(output);
        job.onProgress = std::move(onProgress);
        return dispatch(std::move(job));
    }

private:

    // ── Option validation ─────────────────────────────────────────────────────
    // Validates all user-supplied subprocess option strings on the job.
    // Returns empty string on success, error message on first bad field.
    static std::string validateJobOptions(const ConversionJob& job) {
        // Each optional field is checked only when present. The name passed to
        // validateOption() appears verbatim in any error message shown to the user.
        using PV = PathValidator;
        if (job.videoCodec  && !job.videoCodec->empty())
            if (auto e = PV::validateOption(*job.videoCodec,  "video codec");  !e.empty()) return e;
        if (job.audioCodec  && !job.audioCodec->empty())
            if (auto e = PV::validateOption(*job.audioCodec,  "audio codec");  !e.empty()) return e;
        if (job.pixelFormat && !job.pixelFormat->empty())
            if (auto e = PV::validateOption(*job.pixelFormat, "pixel format"); !e.empty()) return e;
        if (job.videoBitrate && !job.videoBitrate->empty())
            if (auto e = PV::validateOption(*job.videoBitrate, "video bitrate"); !e.empty()) return e;
        if (job.videoMaxRate && !job.videoMaxRate->empty())
            if (auto e = PV::validateOption(*job.videoMaxRate, "video max-rate"); !e.empty()) return e;
        if (job.audioBitrate && !job.audioBitrate->empty())
            if (auto e = PV::validateOption(*job.audioBitrate, "audio bitrate"); !e.empty()) return e;
        if (job.resolution && !job.resolution->empty())
            if (auto e = PV::validateOption(*job.resolution,  "resolution");   !e.empty()) return e;
        if (job.framerate  && !job.framerate->empty())
            if (auto e = PV::validateOption(*job.framerate,   "framerate");    !e.empty()) return e;
        if (job.crf) {
            constexpr int CRF_MIN = 0, CRF_MAX = 63;
            if (*job.crf < CRF_MIN || *job.crf > CRF_MAX)
                return "CRF value " + std::to_string(*job.crf)
                     + " is out of valid range (" + std::to_string(CRF_MIN)
                     + "–" + std::to_string(CRF_MAX) + ")";
        }
        return "";
    }

    // ── Space estimation ──────────────────────────────────────────────────────
    // Returns a conservative upper-bound estimate of output size in bytes.
    // Archives can expand dramatically on decompression; media and documents
    // are generally similar in size to their inputs.
    static uintmax_t estimateOutputBytes(uintmax_t inputBytes, Category inCat, Category outCat) {
        // Decompressing an archive is the worst case — could be 100x in theory,
        // but 10x covers virtually all real-world archives without being absurd.
        if (inCat == Category::Archive || outCat == Category::Archive)
            return inputBytes * 10;

        // Video/audio re-encoding can produce larger output (e.g. lossy → lossless)
        if (inCat == Category::Video || outCat == Category::Video ||
            inCat == Category::Audio || outCat == Category::Audio)
            return inputBytes * 3;

        // Everything else — documents, images, data, 3D models — stays roughly
        // similar in size. 2x is a comfortable buffer.
        return inputBytes * 2;
    }

    // ── Disk space check ──────────────────────────────────────────────────────
    // Returns empty string on success, error message if space is insufficient.
    static std::string checkDiskSpace(const fs::path& outputPath, uintmax_t needed) {
        // Walk up to the nearest existing directory — output dir may not exist yet
        fs::path checkDir = outputPath.parent_path();
        while (!checkDir.empty() && !fs::exists(checkDir))
            checkDir = checkDir.parent_path();
        if (checkDir.empty())
            checkDir = fs::current_path();

        std::error_code ec;
        auto space = fs::space(checkDir, ec);
        if (ec)
            return "";  // Can't determine space — let the conversion attempt proceed

        if (space.available < needed) {
            // Convert to MB for a human-readable message
            auto availMB  = space.available / (1024 * 1024);
            auto neededMB = needed          / (1024 * 1024);
            return "Not enough disk space: need ~" + std::to_string(neededMB) +
                   " MB, only " + std::to_string(availMB) + " MB available";
        }
        return "";
    }

    // ── fallocate (Linux only) ────────────────────────────────────────────────
    // Pre-reserves `size` bytes for the file at `path`.
    // If the filesystem can't accommodate the reservation, this fails
    // immediately — before any conversion work has been done.
    // On Windows this is a no-op; we rely on the fs::space() check alone.
    static void preallocate(const fs::path& path, uintmax_t size) {
#ifdef __linux__
        int fd = open(path.string().c_str(), O_WRONLY | O_CREAT, 0644);
        if (fd < 0) return;
        // fallocate returns -1 on failure (e.g. filesystem doesn't support it)
        // — we silently ignore that and let the conversion proceed normally.
        fallocate(fd, 0, 0, static_cast<off_t>(size));
        close(fd);
#endif
        // Windows: no-op — fs::space() check is the only guard
        (void)path; (void)size;
    }

    // ── Atomic write wrapper ──────────────────────────────────────────────────
    // 1. Estimate required space and check availability (cross-platform)
    // 2. Pre-allocate the temp file (Linux only)
    // 3. Run the converter into the temp file
    // 4. On success: rename temp → real output (atomic)
    // 5. On failure: remove temp, original output is never touched
    static ConversionResult dispatchAtomic(ConversionJob job) {
        fs::path realOutput = job.outputPath;

        // ── Step 1: disk space pre-flight ─────────────────────────────────────
        uintmax_t inputBytes = fs::file_size(job.inputPath);
        uintmax_t needed     = estimateOutputBytes(
            inputBytes,
            job.inputFormat.category,
            job.outputFormat.category
        );

        std::string spaceErr = checkDiskSpace(realOutput, needed);
        if (!spaceErr.empty())
            return ConversionResult::err(spaceErr);

        // ── Step 2: create temp path and pre-allocate ─────────────────────────
        fs::path tempOutput = makeTempPath(realOutput);
        job.outputPath = tempOutput;

        preallocate(tempOutput, needed);

        // ── Step 3: run the converter ─────────────────────────────────────────
        ConversionResult result = route(job);

        if (result.success) {
            // Some converters change the output extension (e.g. PdfRenderer
            // always writes a .zip of page images regardless of the requested
            // extension). Detect this by comparing extensions.
            fs::path srcTemp = tempOutput;
            fs::path dstReal = realOutput;
            if (result.outputPath.extension() != tempOutput.extension()) {
                auto newExt = result.outputPath.extension();
                srcTemp.replace_extension(newExt);
                dstReal = realOutput.parent_path() /
                          (realOutput.stem().string() + newExt.string());
            }

            // ── Step 4: atomic rename ─────────────────────────────────────────
            std::error_code ec;
            fs::rename(srcTemp, dstReal, ec);
            if (ec) {
                fs::remove(srcTemp, ec);
                return ConversionResult::err(
                    "Conversion succeeded but failed to finalise output file: " + ec.message()
                );
            }
            result.outputPath = dstReal;

        } else {
            // ── Step 5: clean up temp on failure ──────────────────────────────
            std::error_code ec;
            fs::remove(tempOutput, ec);
        }

        return result;
    }

    // Generates e.g. /out/video.mp4  →  /out/.video.tmp_3f9a1b.mp4
    // The original extension is kept at the END so that external tools
    // (ffmpeg, ebook-convert, pdftoppm…) can still infer the format from
    // the filename while the write is in progress.
    static fs::path makeTempPath(const fs::path& target) {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<uint32_t> dist(0, 0xFFFFFF);

        char suffix[16];
        std::snprintf(suffix, sizeof(suffix), "%06x", dist(gen));

        std::string tempName =
            "." + target.stem().string() + ".tmp_" + suffix + target.extension().string();

        return target.parent_path() / tempName;
    }

    // ── Converter router ──────────────────────────────────────────────────────
    static ConversionResult route(const ConversionJob& job) {
        Category inCat  = job.inputFormat.category;
        Category outCat = job.outputFormat.category;

        if (inCat == Category::Model3D || outCat == Category::Model3D)
            return ModelConverter::convert(job);

        if ((job.inputFormat.ext == "pdf" || job.inputFormat.ext == "ai") && outCat == Category::Image)
            return PdfRenderer::convert(job);

        if (inCat == Category::Image  || inCat == Category::Video  || inCat == Category::Audio ||
            outCat == Category::Image || outCat == Category::Video || outCat == Category::Audio)
            return MediaConverter::convert(job);

        if ((inCat == Category::Data && outCat == Category::Document) ||
            (inCat == Category::Document && outCat == Category::Data))
            return DocumentConverter::convert(job);

        if (inCat == Category::Data && outCat == Category::Data)
            return DataConverter::convert(job);

        if (inCat == Category::Archive || outCat == Category::Archive)
            return ArchiveConverter::convert(job);

        if (inCat == Category::Document || outCat == Category::Document ||
            inCat == Category::Ebook    || outCat == Category::Ebook)
            return DocumentConverter::convert(job);

        return ConversionResult::err(
            "No converter available for ." + job.inputFormat.ext +
            " → ." + job.outputFormat.ext
        );
    }
};

} // namespace converter