#pragma once

#include "Types.h"
#include "Process.h"
#include <chrono>
#include <sstream>

namespace converter {

class MediaConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        if (job.onProgress) job.onProgress(0.1f, "Converting...");

        auto args = buildFFmpegArgs(job);
        int ret = Process::run("ffmpeg", args);

        if (ret != 0)
            return ConversionResult::err("FFmpeg conversion failed");

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(end - start).count();

        auto result = ConversionResult::ok(job.outputPath, secs);
        result.inputBytes = fs::file_size(job.inputPath);
        if (fs::exists(job.outputPath))
            result.outputBytes = fs::file_size(job.outputPath);

        return result;
    }

private:
    struct Defaults {
        std::string videoCodec;
        std::string audioCodec;
        std::string pixelFormat;
        int         crf = -1;
    };

    static Defaults defaultsFor(const std::string& outExt) {
        if (outExt == "mp4" || outExt == "m4v")
            return { "libx264", "aac", "yuv420p", 18 };
        if (outExt == "mkv")
            return { "libx264", "aac", "yuv420p", 18 };
        if (outExt == "webm")
            return { "libvpx-vp9", "libopus", "yuv420p", 20 };
        if (outExt == "mov")
            return { "libx264", "aac", "yuv420p", 18 };
        if (outExt == "avi")
            return { "mpeg4", "libmp3lame", "yuv420p", -1 };
        if (outExt == "gif")
            return { "", "", "", -1 };
        if (outExt == "mp3")  return { "", "libmp3lame", "", -1 };
        if (outExt == "aac")  return { "", "aac",        "", -1 };
        if (outExt == "ogg")  return { "", "libvorbis",  "", -1 };
        if (outExt == "opus") return { "", "libopus",    "", -1 };
        if (outExt == "flac") return { "", "flac",       "", -1 };
        if (outExt == "wav")  return { "", "pcm_s16le",  "", -1 };
        if (outExt == "m4a")  return { "", "aac",        "", -1 };
        return { "", "", "", -1 };
    }

    // ── ICO ───────────────────────────────────────────────────────────────────
    static std::vector<std::string> buildIcoArgs(const ConversionJob& job) {
        return {
            "-y", "-i", job.inputPath.string(),
            "-filter_complex",
            "[0:v]scale=256:256:flags=lanczos[s256]"
            ";[0:v]scale=48:48:flags=lanczos[s48]"
            ";[0:v]scale=32:32:flags=lanczos[s32]"
            ";[0:v]scale=16:16:flags=lanczos[s16]",
            "-map", "[s256]", "-map", "[s48]", "-map", "[s32]", "-map", "[s16]",
            job.outputPath.string()
        };
    }

    // ── GIF: two-pass palettegen ───────────────────────────────────────────────
    // Two-pass GIF can't be a single Process::run call.
    // We run pass1 and pass2 sequentially.
    static ConversionResult convertGif(const ConversionJob& job) {
        std::string scaleFilter;
        if (job.resolution) {
            auto x = job.resolution->find('x');
            if (x != std::string::npos)
                scaleFilter = "scale=" + job.resolution->substr(0, x)
                            + ":" + job.resolution->substr(x + 1) + ",";
        }
        std::string fpsFilter;
        if (job.framerate)
            fpsFilter = "fps=" + *job.framerate + ",";

        std::string filters = fpsFilter + scaleFilter;

        fs::path palette = fs::temp_directory_path() / ("anyfile_palette_" +
            std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) + ".png");

        // Pass 1 — generate palette
        std::vector<std::string> pass1 = {
            "-y", "-i", job.inputPath.string(),
            "-vf", filters + "palettegen",
            palette.string()
        };
        if (Process::run("ffmpeg", pass1) != 0) {
            fs::remove(palette);
            return ConversionResult::err("FFmpeg GIF palette generation failed");
        }

        // Pass 2 — render with palette
        std::vector<std::string> pass2 = {
            "-y",
            "-i", job.inputPath.string(),
            "-i", palette.string(),
            "-lavfi", filters + "paletteuse",
            job.outputPath.string()
        };
        int ret = Process::run("ffmpeg", pass2);
        fs::remove(palette);

        if (ret != 0)
            return ConversionResult::err("FFmpeg GIF render failed");

        return ConversionResult::ok(job.outputPath);
    }

    // ── Main args builder ─────────────────────────────────────────────────────
    static std::vector<std::string> buildFFmpegArgs(const ConversionJob& job) {
        const std::string& outExt = job.outputFormat.ext;

        Defaults def = defaultsFor(outExt);

        auto resolve = [](const std::optional<std::string>& ov,
                          const std::string& d) -> std::string {
            return ov ? *ov : d;
        };

        std::string vcodec = resolve(job.videoCodec,  def.videoCodec);
        std::string acodec = resolve(job.audioCodec,  def.audioCodec);
        std::string pix    = resolve(job.pixelFormat, def.pixelFormat);
        int         crf    = job.crf ? *job.crf : def.crf;

        std::vector<std::string> args;
        args.push_back("-y");
        args.push_back("-i");
        args.push_back(job.inputPath.string());

        if (!vcodec.empty()) { args.push_back("-c:v"); args.push_back(vcodec); }
        if (!vcodec.empty() && (outExt == "mp4" || outExt == "mkv" || outExt == "mov")) {
            args.push_back("-preset"); args.push_back("slow");
        }
        if (!acodec.empty()) { args.push_back("-c:a"); args.push_back(acodec); }
        if (crf >= 0)        { args.push_back("-crf"); args.push_back(std::to_string(crf)); }
        if (!pix.empty())    { args.push_back("-pix_fmt"); args.push_back(pix); }

        if (job.videoBitrate) { args.push_back("-b:v"); args.push_back(*job.videoBitrate); }
        if (job.audioBitrate) { args.push_back("-b:a"); args.push_back(*job.audioBitrate); }
        else if (!acodec.empty()) { args.push_back("-b:a"); args.push_back("320k"); }

        if (job.resolution) {
            auto x = job.resolution->find('x');
            if (x != std::string::npos) {
                args.push_back("-vf");
                args.push_back("scale=" + job.resolution->substr(0, x)
                              + ":" + job.resolution->substr(x + 1));
            }
        }

        if (job.framerate) { args.push_back("-r"); args.push_back(*job.framerate); }

        args.push_back(job.outputPath.string());
        return args;
    }

public:
    // Re-expose convert so GIF can return early with a full ConversionResult
    static ConversionResult convertDispatch(const ConversionJob& job) {
        const std::string& outExt = job.outputFormat.ext;

        auto start = std::chrono::steady_clock::now();
        if (job.onProgress) job.onProgress(0.1f, "Converting...");

        ConversionResult result;
        if (outExt == "gif") {
            result = convertGif(job);
        } else {
            std::vector<std::string> args;
            if (outExt == "ico")
                args = buildIcoArgs(job);
            else
                args = buildFFmpegArgs(job);

            int ret = Process::run("ffmpeg", args);
            result = (ret == 0)
                ? ConversionResult::ok(job.outputPath)
                : ConversionResult::err("FFmpeg conversion failed");
        }

        if (!result.success) return result;

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        result.durationSeconds = std::chrono::duration<double>(end - start).count();
        result.inputBytes      = fs::file_size(job.inputPath);
        if (fs::exists(job.outputPath))
            result.outputBytes = fs::file_size(job.outputPath);

        return result;
    }
};

} // namespace converter