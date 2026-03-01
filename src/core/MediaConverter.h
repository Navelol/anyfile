#pragma once

#include "Types.h"
#include <cstdlib>
#include <chrono>
#include <sstream>

namespace converter {

class MediaConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        if (job.onProgress) job.onProgress(0.1f, "Converting...");

        std::string cmd = buildFFmpegCmd(job);
        int ret = std::system(cmd.c_str());

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
    // ── Sensible defaults per output format ──────────────────────────────────
    struct Defaults {
        std::string videoCodec;
        std::string audioCodec;
        std::string pixelFormat;
        int         crf = -1;  // -1 means don't apply
    };

    static Defaults defaultsFor(const std::string& outExt) {
        // mp4 / m4v — H.264 + AAC, widest compatibility
        if (outExt == "mp4" || outExt == "m4v")
            return { "libx264", "aac", "yuv420p", 23 };

        // mkv — H.264 + AAC (safe default; user can override to x265 etc.)
        if (outExt == "mkv")
            return { "libx264", "aac", "yuv420p", 23 };

        // webm — VP9 + Opus
        if (outExt == "webm")
            return { "libvpx-vp9", "libopus", "yuv420p", 31 };

        // mov — H.264 + AAC (QuickTime compatible)
        if (outExt == "mov")
            return { "libx264", "aac", "yuv420p", 23 };

        // avi — MPEG-4 + MP3 (legacy format, keep it compatible)
        if (outExt == "avi")
            return { "mpeg4", "libmp3lame", "yuv420p", -1 };

        // gif — no audio, palettegen gives much better quality
        if (outExt == "gif")
            return { "", "", "", -1 };

        // audio-only outputs — no video codec needed
        if (outExt == "mp3")  return { "", "libmp3lame", "", -1 };
        if (outExt == "aac")  return { "", "aac",        "", -1 };
        if (outExt == "ogg")  return { "", "libvorbis",  "", -1 };
        if (outExt == "opus") return { "", "libopus",    "", -1 };
        if (outExt == "flac") return { "", "flac",       "", -1 };
        if (outExt == "wav")  return { "", "pcm_s16le",  "", -1 };
        if (outExt == "m4a")  return { "", "aac",        "", -1 };

        // image outputs
        if (outExt == "png")  return { "", "", "", -1 };
        if (outExt == "jpg" || outExt == "jpeg") return { "", "", "", -1 };
        if (outExt == "webp") return { "", "", "", -1 };

        // fallback — let FFmpeg decide
        return { "", "", "", -1 };
    }

    // ── GIF gets special treatment — two-pass palettegen ─────────────────────
    static std::string buildGifCmd(const ConversionJob& job) {
        // Build scale filter if resolution was specified
        std::string scaleFilter;
        if (job.resolution) {
            // Convert "WxH" to FFmpeg scale syntax
            std::string res = *job.resolution;
            auto x = res.find('x');
            if (x != std::string::npos)
                scaleFilter = "scale=" + res.substr(0, x) + ":" + res.substr(x + 1) + ",";
        }

        std::string fpsFilter;
        if (job.framerate)
            fpsFilter = "fps=" + *job.framerate + ",";

        std::string filters = fpsFilter + scaleFilter;

        fs::path palette = fs::temp_directory_path() / ("everyfile_palette_" +
            std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) + ".png");

        // Pass 1: generate palette
        std::string pass1 =
            "ffmpeg -y -i \"" + job.inputPath.string() + "\""
            " -vf \"" + filters + "palettegen\""
            " \"" + palette.string() + "\" 2>/dev/null";

        // Pass 2: render gif using palette
        std::string pass2 =
            "ffmpeg -y -i \"" + job.inputPath.string() + "\""
            " -i \"" + palette.string() + "\""
            " -lavfi \"" + filters + "paletteuse\""
            " \"" + job.outputPath.string() + "\" 2>/dev/null"
            " && rm -f \"" + palette.string() + "\"";

        return pass1 + " && " + pass2;
    }

    // ── Main command builder ──────────────────────────────────────────────────
    static std::string buildFFmpegCmd(const ConversionJob& job) {
        const std::string& outExt = job.outputFormat.ext;

        // GIF is special
        if (outExt == "gif")
            return buildGifCmd(job);

        Defaults def = defaultsFor(outExt);

        // Resolve: job override wins, else default, else omit
        auto resolve = [](const std::optional<std::string>& override,
                          const std::string& def) -> std::string {
            if (override) return *override;
            return def;
        };

        std::string vcodec = resolve(job.videoCodec,   def.videoCodec);
        std::string acodec = resolve(job.audioCodec,   def.audioCodec);
        std::string pix    = resolve(job.pixelFormat,  def.pixelFormat);
        int         crf    = job.crf ? *job.crf : def.crf;

        std::ostringstream cmd;
        cmd << "ffmpeg -y -i \"" << job.inputPath.string() << "\"";

        // Video codec
        if (!vcodec.empty())
            cmd << " -c:v " << vcodec;

        // Audio codec
        if (!acodec.empty())
            cmd << " -c:a " << acodec;

        // CRF (quality)
        if (crf >= 0)
            cmd << " -crf " << crf;

        // Pixel format
        if (!pix.empty())
            cmd << " -pix_fmt " << pix;

        // Video bitrate
        if (job.videoBitrate)
            cmd << " -b:v " << *job.videoBitrate;

        // Audio bitrate
        if (job.audioBitrate)
            cmd << " -b:a " << *job.audioBitrate;

        // Resolution
        if (job.resolution) {
            std::string res = *job.resolution;
            auto x = res.find('x');
            if (x != std::string::npos)
                cmd << " -vf scale=" << res.substr(0, x) << ":" << res.substr(x + 1);
        }

        // Framerate
        if (job.framerate)
            cmd << " -r " << *job.framerate;

        cmd << " \"" << job.outputPath.string() << "\" 2>/dev/null";

        return cmd.str();
    }
};

} // namespace converter