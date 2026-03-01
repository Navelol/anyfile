#pragma once

#include "Types.h"
#include "FormatRegistry.h"
#include "MediaConverter.h"
#include "ModelConverter.h"
#include "DataConverter.h"

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

        auto outFmt = reg.detect(job.outputPath);
        if (!outFmt)
            return ConversionResult::err("Unknown output format: " + job.outputPath.extension().string());

        job.inputFormat  = *inFmt;
        job.outputFormat = *outFmt;

        // Check the conversion is supported
        if (!reg.canConvert(inFmt->ext, outFmt->ext)) {
            return ConversionResult::err(
                "Conversion from ." + inFmt->ext + " to ." + outFmt->ext + " is not supported"
            );
        }

        // Ensure output directory exists
        auto outDir = job.outputPath.parent_path();
        if (!outDir.empty()) fs::create_directories(outDir);

        // Route to the right converter
        return route(job);
    }

    // Convenience overload — derive output format from extension string
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
    static ConversionResult route(const ConversionJob& job) {
        Category inCat  = job.inputFormat.category;
        Category outCat = job.outputFormat.category;

        // ── 3D models ─────────────────────────────────────────────────────────
        if (inCat == Category::Model3D || outCat == Category::Model3D) {
            return ModelConverter::convert(job);
        }

        // ── Media: image, video, audio ─────────────────────────────────────
        // FFmpeg handles all of these — including cross-category like video→audio
        if (inCat == Category::Image  || inCat == Category::Video  || inCat == Category::Audio ||
            outCat == Category::Image || outCat == Category::Video || outCat == Category::Audio) {
            return MediaConverter::convert(job);
        }

        // ── Data formats (JSON, XML, YAML, CSV) ───────────────────────────
        if (inCat == Category::Data && outCat == Category::Data) {
                return DataConverter::convert(job);
        }

        // ── Archives ──────────────────────────────────────────────────────
        if (inCat == Category::Archive || outCat == Category::Archive) {
            // TODO: implement ArchiveConverter using libarchive
            return ConversionResult::err("Archive conversion not yet implemented");
        }

        return ConversionResult::err(
            "No converter available for ." + job.inputFormat.ext +
            " → ." + job.outputFormat.ext
        );
    }
};

} // namespace converter
