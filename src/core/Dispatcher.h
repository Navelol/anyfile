#pragma once

#include "Types.h"
#include "FormatRegistry.h"
#include "MediaConverter.h"
#include "ModelConverter.h"
#include "DataConverter.h"
#include "DocumentConverter.h"
#include "ArchiveConverter.h"
#include "PdfRenderer.h"
#include <random>

namespace converter {

class Dispatcher {
public:

    // Main entry point — takes a job and routes it to the right converter
    static ConversionResult dispatch(ConversionJob job) {

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

    // ── Atomic write wrapper ──────────────────────────────────────────────────
    // Converts to a temp file, then renames to final path on success.
    // Rename is a single OS syscall — readers always see either the old
    // complete file or the new complete file, never a partial write.
    static ConversionResult dispatchAtomic(ConversionJob job) {
        fs::path realOutput = job.outputPath;

        // Build a temp path in the same directory so rename() stays on one filesystem
        fs::path tempOutput = makeTempPath(realOutput);
        job.outputPath = tempOutput;

        ConversionResult result = route(job);

        if (result.success) {
            // Some converters change the output extension (e.g. PdfRenderer
            // always writes a .zip of page images regardless of the requested
            // extension).  Detect this by comparing the extension the converter
            // reported with the extension of the temp file we gave it.
            fs::path srcTemp = tempOutput;
            fs::path dstReal = realOutput;
            if (result.outputPath.extension() != tempOutput.extension()) {
                auto newExt = result.outputPath.extension();
                srcTemp.replace_extension(newExt);
                dstReal = realOutput.parent_path() /
                          (realOutput.stem().string() + newExt.string());
            }

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
            // Clean up the temp file on failure (best-effort)
            std::error_code ec;
            fs::remove(tempOutput, ec);
        }

        return result;
    }

    // Generates e.g. /out/video.mp4  →  /out/.video.tmp_3f9a1b.mp4
    // The original extension is kept at the END so that external tools (ffmpeg,
    // ebook-convert, pdftoppm …) can still infer the container/format from the
    // filename while the write is in progress.
    static fs::path makeTempPath(const fs::path& target) {
        // Random 6-hex-char suffix — avoids collisions when two jobs
        // target the same output path concurrently
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<uint32_t> dist(0, 0xFFFFFF);

        char suffix[16];
        std::snprintf(suffix, sizeof(suffix), "%06x", dist(gen));

        // Pattern: .<stem>.tmp_<hex><ext>  e.g. .video.tmp_3f9a1b.mp4
        std::string tempName =
            "." + target.stem().string() + ".tmp_" + suffix + target.extension().string();

        return target.parent_path() / tempName;
    }

    // ── Converter router ──────────────────────────────────────────────────────
    static ConversionResult route(const ConversionJob& job) {
        Category inCat  = job.inputFormat.category;
        Category outCat = job.outputFormat.category;

        // ── 3D models ─────────────────────────────────────────────────────────
        if (inCat == Category::Model3D || outCat == Category::Model3D)
            return ModelConverter::convert(job);

        // ── PDF → Image ───────────────────────────────────────────────────────
        if (job.inputFormat.ext == "pdf" && outCat == Category::Image)
            return PdfRenderer::convert(job);

        // ── Media: image, video, audio ────────────────────────────────────────
        if (inCat == Category::Image  || inCat == Category::Video  || inCat == Category::Audio ||
            outCat == Category::Image || outCat == Category::Video || outCat == Category::Audio)
            return MediaConverter::convert(job);

        // ── Cross-category: spreadsheet ↔ data ───────────────────────────────
        if ((inCat == Category::Data && outCat == Category::Document) ||
            (inCat == Category::Document && outCat == Category::Data))
            return DocumentConverter::convert(job);

        // ── Data formats (JSON, XML, YAML, CSV…) ──────────────────────────────
        if (inCat == Category::Data && outCat == Category::Data)
            return DataConverter::convert(job);

        // ── Archives ──────────────────────────────────────────────────────────
        if (inCat == Category::Archive || outCat == Category::Archive)
            return ArchiveConverter::convert(job);

        // ── Documents & Ebooks ────────────────────────────────────────────────
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