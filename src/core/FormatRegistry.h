#pragma once

#include "Types.h"
#include <unordered_map>
#include <unordered_set>
#include <fstream>
#include <cstring>

// libmagic — optional but strongly recommended.
// Install: sudo apt install libmagic-dev  /  choco install file  (Windows via MSYS2)
#if __has_include(<magic.h>)
#  include <magic.h>
#  define ANYFILE_HAS_LIBMAGIC 1
#else
#  define ANYFILE_HAS_LIBMAGIC 0
#endif

namespace converter {

class FormatRegistry {
public:
    static FormatRegistry& instance() {
        static FormatRegistry reg;
        return reg;
    }

    // ── detect() ─────────────────────────────────────────────────────────────
    // For files that exist on disk: tries magic-number detection first,
    // falls back to extension if magic is inconclusive.
    // For output paths (file doesn't exist yet): extension only.
    std::optional<Format> detect(const fs::path& path) const {
        if (fs::exists(path)) {
            // 1. Try libmagic (when available) — most reliable for known MIME types
            auto byMagic = detectByMagic(path);
            if (byMagic) return byMagic;

            // 2. Fall back to hand-rolled byte sniffer — catches cases where
            //    libmagic is installed but returns nullopt (e.g. truncated/minimal
            //    files, or formats it doesn't recognise well)
            auto byBytes = detectByBytes(path);
            if (byBytes) return byBytes;

            // 3. Fall back to extension
        }
        return detectByExtension(path);
    }

    // ── detectByExtension() ──────────────────────────────────────────────────
    // Public so callers can force extension-only lookup (e.g. for output paths).
    std::optional<Format> detectByExtension(const fs::path& path) const {
        auto ext = path.extension().string();
        if (ext.empty()) return std::nullopt;

        std::string key = ext.substr(1);
        for (auto& c : key) c = std::tolower((unsigned char)c);

        auto it = m_map.find(key);
        if (it == m_map.end()) return std::nullopt;
        return it->second;
    }

    // Get valid output formats for a given input format
    std::vector<std::string> targetsFor(const std::string& inputExt) const {
        auto it = m_targets.find(inputExt);
        if (it == m_targets.end()) return {};
        return { it->second.begin(), it->second.end() };
    }

    bool canConvert(const std::string& from, const std::string& to) const {
        auto it = m_targets.find(from);
        if (it == m_targets.end()) return false;
        return it->second.count(to) > 0;
    }

private:
    FormatRegistry() { buildRegistry(); }

    // ── Magic-number detection ────────────────────────────────────────────────
    std::optional<Format> detectByMagic(const fs::path& path) const {
#if ANYFILE_HAS_LIBMAGIC
        // magic_open / magic_load are cheap — the database is loaded once and
        // the cookie is used for a single call then closed.
        // For a long-running app you'd want to cache the cookie; here we keep
        // it simple and correct (thread-safe: each call owns its cookie).
        magic_t cookie = magic_open(MAGIC_MIME_TYPE | MAGIC_SYMLINK);
        if (!cookie) return std::nullopt;

        if (magic_load(cookie, nullptr) != 0) {
            magic_close(cookie);
            return std::nullopt;
        }

        const char* mime = magic_file(cookie, path.string().c_str());
        std::optional<Format> result;
        if (mime) {
            result = mimeToFormat(std::string(mime));
        }
        magic_close(cookie);
        return result;
#else
        // ── Fallback: hand-rolled magic bytes (covers common formats) ─────────
        // Used when libmagic isn't available (e.g. bare Windows build without MSYS2 file pkg).
        return detectByBytes(path);
#endif
    }

    // ── Hand-rolled byte sniffer (libmagic fallback) ──────────────────────────
    // Covers the formats most likely to be misnamed or extensionless.
    static std::optional<Format> detectByBytes(const fs::path& path) {
        std::ifstream f(path.string(), std::ios::binary);
        if (!f) return std::nullopt;

        unsigned char buf[32] = {};
        f.read(reinterpret_cast<char*>(buf), sizeof(buf));
        auto n = static_cast<size_t>(f.gcount());
        if (n < 4) return std::nullopt;

        // ── Archives ──────────────────────────────────────────────────────────
        if (buf[0]=='P' && buf[1]=='K' && buf[2]==0x03 && buf[3]==0x04)
            return fmt("zip", Category::Archive, "application/zip");
        if (buf[0]==0x1F && buf[1]==0x8B)
            return fmt("gz",  Category::Archive, "application/gzip");
        if (buf[0]=='B' && buf[1]=='Z' && buf[2]=='h')
            return fmt("bz2", Category::Archive, "application/x-bzip2");
        if (buf[0]==0xFD && buf[1]=='7' && buf[2]=='z' && buf[3]=='X' && buf[4]=='Z')
            return fmt("xz",  Category::Archive, "application/x-xz");
        if (buf[0]=='7' && buf[1]=='z' && buf[2]==0xBC && buf[3]==0xAF)
            return fmt("7z",  Category::Archive, "application/x-7z-compressed");
        if (buf[0]==0x28 && buf[1]==0xB5 && buf[2]==0x2F && buf[3]==0xFD)
            return fmt("zst", Category::Archive, "application/zstd");
        if (buf[0]=='R' && buf[1]=='a' && buf[2]=='r' && buf[3]=='!')
            return fmt("rar", Category::Archive, "application/x-rar-compressed");
        // tar: check ustar signature at offset 257
        {
            std::ifstream tf(path.string(), std::ios::binary);
            unsigned char tbuf[512] = {};
            tf.read(reinterpret_cast<char*>(tbuf), 512);
            if (tf.gcount() >= 262 &&
                tbuf[257]=='u' && tbuf[258]=='s' && tbuf[259]=='t' && tbuf[260]=='a' && tbuf[261]=='r')
                return fmt("tar", Category::Archive, "application/x-tar");
        }

        // ── Images ────────────────────────────────────────────────────────────
        if (buf[0]==0x89 && buf[1]=='P' && buf[2]=='N' && buf[3]=='G')
            return fmt("png",  Category::Image, "image/png");
        if (buf[0]==0xFF && buf[1]==0xD8 && buf[2]==0xFF)
            return fmt("jpg",  Category::Image, "image/jpeg");
        if (buf[0]=='G' && buf[1]=='I' && buf[2]=='F')
            return fmt("gif",  Category::Image, "image/gif");
        if (buf[0]=='R' && buf[1]=='I' && buf[2]=='F' && buf[3]=='F' && n>=12 &&
            buf[8]=='W' && buf[9]=='E' && buf[10]=='B' && buf[11]=='P')
            return fmt("webp", Category::Image, "image/webp");
        if (buf[0]=='B' && buf[1]=='M')
            return fmt("bmp",  Category::Image, "image/bmp");
        if ((buf[0]=='I' && buf[1]=='I' && buf[2]==0x2A && buf[3]==0x00) ||
            (buf[0]=='M' && buf[1]=='M' && buf[2]==0x00 && buf[3]==0x2A))
            return fmt("tiff", Category::Image, "image/tiff");
        if (n>=12 && buf[0]==0x00 && buf[1]==0x00 && buf[2]==0x01 && buf[3]==0x00)
            return fmt("ico",  Category::Image, "image/x-icon");

        // ── Video / Audio ─────────────────────────────────────────────────────
        // MP4/M4A/MOV — ftyp box
        if (n>=8 && buf[4]=='f' && buf[5]=='t' && buf[6]=='y' && buf[7]=='p') {
            // sub-brand at byte 8
            if (n>=12) {
                std::string brand(reinterpret_cast<char*>(buf+8), 4);
                if (brand=="qt  ") return fmt("mov", Category::Video, "video/quicktime");
                if (brand=="M4A ") return fmt("m4a", Category::Audio, "audio/mp4");
                if (brand=="M4V ") return fmt("m4v", Category::Video, "video/x-m4v");
            }
            return fmt("mp4", Category::Video, "video/mp4");
        }
        if (buf[0]==0x1A && buf[1]==0x45 && buf[2]==0xDF && buf[3]==0xA3)
            return fmt("mkv", Category::Video, "video/x-matroska"); // also webm — close enough
        if (buf[0]=='R' && buf[1]=='I' && buf[2]=='F' && buf[3]=='F' && n>=12 &&
            buf[8]=='A' && buf[9]=='V' && buf[10]=='I' && buf[11]==' ')
            return fmt("avi", Category::Video, "video/x-msvideo");
        if (buf[0]=='R' && buf[1]=='I' && buf[2]=='F' && buf[3]=='F' && n>=12 &&
            buf[8]=='W' && buf[9]=='A' && buf[10]=='V' && buf[11]=='E')
            return fmt("wav", Category::Audio, "audio/wav");
        if (buf[0]=='I' && buf[1]=='D' && buf[2]=='3')
            return fmt("mp3", Category::Audio, "audio/mpeg");
        if (buf[0]==0xFF && (buf[1]&0xE0)==0xE0)  // MPEG sync
            return fmt("mp3", Category::Audio, "audio/mpeg");
        if (buf[0]=='f' && buf[1]=='L' && buf[2]=='a' && buf[3]=='C')
            return fmt("flac", Category::Audio, "audio/flac");
        if (buf[0]=='O' && buf[1]=='g' && buf[2]=='g' && buf[3]=='S')
            return fmt("ogg", Category::Audio, "audio/ogg");

        // ── Documents ─────────────────────────────────────────────────────────
        if (buf[0]=='%' && buf[1]=='P' && buf[2]=='D' && buf[3]=='F')
            return fmt("pdf", Category::Document, "application/pdf");
        // Office Open XML (.docx/.xlsx/.pptx are zip-based — already caught by PK above,
        // but if someone passed the right file we can't distinguish without reading more.
        // Leave to extension fallback for OOXML.)

        // ── 3D ────────────────────────────────────────────────────────────────
        // GLB
        if (buf[0]==0x67 && buf[1]==0x6C && buf[2]==0x54 && buf[3]==0x46)
            return fmt("glb", Category::Model3D, "model/gltf-binary");

        // NOTE: '{' (JSON) and '<' (XML-like) are intentionally NOT sniffed here.
        // Too many unrelated formats start with those bytes: FB2, SVG, HTML,
        // COLLADA, GLTF, etc. all begin with '<'; the byte alone can't distinguish
        // them, so we let the extension fallback handle all text-based formats.

        return std::nullopt;  // inconclusive — caller will try extension
    }

    // ── MIME → Format (used by libmagic path) ─────────────────────────────────
    std::optional<Format> mimeToFormat(const std::string& mime) const {
        // Strip parameters like "text/html; charset=utf-8"
        std::string m = mime.substr(0, mime.find(';'));
        while (!m.empty() && m.back() == ' ') m.pop_back();

        // text/plain is too generic — libmagic returns it for any plain-text file
        // that lacks a specific magic signature (XML without declaration, YAML,
        // TOML, INI, ENV, etc.).  Treat it as inconclusive so detect() falls
        // back to the file's extension instead.
        if (m == "text/plain") return std::nullopt;

        auto it = m_mimeMap.find(m);
        if (it != m_mimeMap.end()) return it->second;
        return std::nullopt;
    }

    // ── Helper ────────────────────────────────────────────────────────────────
    static Format fmt(const std::string& ext, Category cat, const std::string& mime) {
        return { ext, cat, mime };
    }

    // ── Registry builder ──────────────────────────────────────────────────────
    void buildRegistry() {
        // ── Images ───────────────────────────────────────────────────────────
        reg("png",  Category::Image, "image/png");
        reg("jpg",  Category::Image, "image/jpeg");
        reg("jpeg", Category::Image, "image/jpeg");
        reg("webp", Category::Image, "image/webp");
        reg("bmp",  Category::Image, "image/bmp");
        reg("tiff", Category::Image, "image/tiff");
        reg("tif",  Category::Image, "image/tiff");
        reg("gif",  Category::Image, "image/gif");
        reg("heic", Category::Image, "image/heic");
        reg("avif", Category::Image, "image/avif");
        reg("exr",  Category::Image, "image/x-exr");
        reg("hdr",  Category::Image, "image/vnd.radiance");
        reg("tga",  Category::Image, "image/x-tga");
        reg("ico",  Category::Image, "image/x-icon");
        reg("svg",  Category::Image, "image/svg+xml");
        reg("raw",  Category::Image, "image/x-raw");
        reg("cr2",  Category::Image, "image/x-canon-cr2");
        reg("nef",  Category::Image, "image/x-nikon-nef");
        reg("arw",  Category::Image, "image/x-sony-arw");
        reg("dng",  Category::Image, "image/x-adobe-dng");

        // ── Video ─────────────────────────────────────────────────────────────
        reg("mp4",  Category::Video, "video/mp4");
        reg("mov",  Category::Video, "video/quicktime");
        reg("avi",  Category::Video, "video/x-msvideo");
        reg("mkv",  Category::Video, "video/x-matroska");
        reg("webm", Category::Video, "video/webm");
        reg("flv",  Category::Video, "video/x-flv");
        reg("wmv",  Category::Video, "video/x-ms-wmv");
        reg("m4v",  Category::Video, "video/x-m4v");
        reg("3gp",  Category::Video, "video/3gpp");
        reg("ogv",  Category::Video, "video/ogg");
        reg("ts",   Category::Video, "video/mp2t");
        reg("vob",  Category::Video, "video/dvd");
        reg("rmvb", Category::Video, "video/x-pn-realvideo");

        // ── Audio ─────────────────────────────────────────────────────────────
        reg("mp3",  Category::Audio, "audio/mpeg");
        reg("wav",  Category::Audio, "audio/wav");
        reg("flac", Category::Audio, "audio/flac");
        reg("aac",  Category::Audio, "audio/aac");
        reg("ogg",  Category::Audio, "audio/ogg");
        reg("opus", Category::Audio, "audio/opus");
        reg("m4a",  Category::Audio, "audio/mp4");
        reg("wma",  Category::Audio, "audio/x-ms-wma");
        reg("aiff", Category::Audio, "audio/aiff");
        reg("caf",  Category::Audio, "audio/x-caf");

        // ── 3D Models ─────────────────────────────────────────────────────────
        reg("fbx",  Category::Model3D, "model/fbx");
        reg("obj",  Category::Model3D, "model/obj");
        reg("glb",  Category::Model3D, "model/gltf-binary");
        reg("gltf", Category::Model3D, "model/gltf+json");
        reg("stl",  Category::Model3D, "model/stl");
        reg("dae",  Category::Model3D, "model/vnd.collada+xml");
        reg("ply",  Category::Model3D, "model/ply");
        reg("3ds",  Category::Model3D, "model/x-3ds");
        reg("blend", Category::Model3D, "model/blend");
        reg("usd",  Category::Model3D, "model/vnd.usd");
        reg("usdz", Category::Model3D, "model/vnd.usdz+zip");

        // ── Archives ──────────────────────────────────────────────────────────
        reg("zip",  Category::Archive, "application/zip");
        reg("tar",  Category::Archive, "application/x-tar");
        reg("gz",   Category::Archive, "application/gzip");
        reg("bz2",  Category::Archive, "application/x-bzip2");
        reg("xz",   Category::Archive, "application/x-xz");
        reg("7z",   Category::Archive, "application/x-7z-compressed");
        reg("rar",  Category::Archive, "application/x-rar-compressed");
        reg("zst",  Category::Archive, "application/zstd");
        reg("tgz",  Category::Archive, "application/x-tar");
        reg("tbz2", Category::Archive, "application/x-bzip2");
        reg("txz",  Category::Archive, "application/x-xz");
        reg("lz4",  Category::Archive, "application/x-lz4");
        reg("lzma", Category::Archive, "application/x-lzma");

        // ── Data ──────────────────────────────────────────────────────────────
        reg("json", Category::Data, "application/json");
        reg("xml",  Category::Data, "application/xml");
        reg("yaml", Category::Data, "application/yaml");
        reg("yml",  Category::Data, "application/yaml");
        reg("csv",  Category::Data, "text/csv");
        reg("tsv",  Category::Data, "text/tab-separated-values");
        reg("toml", Category::Data, "application/toml");
        reg("ini",  Category::Data, "text/x-ini");
        reg("env",  Category::Data, "text/x-dotenv");

        // ── Documents ─────────────────────────────────────────────────────────
        reg("pdf",  Category::Document, "application/pdf");
        reg("docx", Category::Document, "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
        reg("doc",  Category::Document, "application/msword");
        reg("odt",  Category::Document, "application/vnd.oasis.opendocument.text");
        reg("rtf",  Category::Document, "application/rtf");
        reg("xlsx", Category::Document, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        reg("xls",  Category::Document, "application/vnd.ms-excel");
        reg("ods",  Category::Document, "application/vnd.oasis.opendocument.spreadsheet");
        reg("pptx", Category::Document, "application/vnd.openxmlformats-officedocument.presentationml.presentation");
        reg("ppt",  Category::Document, "application/vnd.ms-powerpoint");
        reg("odp",  Category::Document, "application/vnd.oasis.opendocument.presentation");
        reg("txt",  Category::Document, "text/plain");
        reg("html", Category::Document, "text/html");
        reg("htm",  Category::Document, "text/html");
        reg("md",       Category::Document, "text/markdown");
        reg("markdown", Category::Document, "text/markdown");
        reg("rst",      Category::Document, "text/x-rst");
        reg("tex",      Category::Document, "application/x-tex");
        reg("latex",    Category::Document, "application/x-latex");

        // ── Ebooks ────────────────────────────────────────────────────────────
        reg("epub", Category::Ebook, "application/epub+zip");
        reg("mobi", Category::Ebook, "application/x-mobipocket-ebook");
        reg("azw3", Category::Ebook, "application/vnd.amazon.ebook");
        reg("azw",  Category::Ebook, "application/vnd.amazon.ebook");
        reg("fb2",  Category::Ebook, "application/x-fictionbook");
        reg("djvu", Category::Ebook, "image/vnd.djvu");
        reg("lit",  Category::Ebook, "application/x-ms-reader");

        // ── Build MIME → Format reverse map ──────────────────────────────────
        // (preferred canonical ext per MIME — first one registered wins)
        for (auto& [ext, f] : m_map) {
            if (!m_mimeMap.count(f.mimeType))
                m_mimeMap[f.mimeType] = f;
        }

        // ── Conversion target map ─────────────────────────────────────────────
        // Images
        targets("png",  {"jpg","webp","bmp","tiff","gif","avif","tga","ico"});
        targets("jpg",  {"png","webp","bmp","tiff","gif","avif","ico"});
        targets("jpeg", {"png","webp","bmp","tiff","gif","avif","ico"});
        targets("webp", {"png","jpg","bmp","tiff","gif","ico"});
        targets("bmp",  {"png","jpg","webp","tiff","ico"});
        targets("tiff", {"png","jpg","webp","bmp","ico"});
        targets("gif",  {"png","jpg","webp","mp4","webm"});
        targets("heic", {"png","jpg","webp","ico"});
        targets("avif", {"png","jpg","webp","ico"});
        targets("ico",  {"png","jpg","webp","bmp","tiff","gif"});
        targets("tga",  {"png","jpg","webp","bmp","ico"});
        targets("svg",  {"png","jpg","webp","ico"});
        targets("raw",  {"jpg","png","tiff","webp"});
        targets("cr2",  {"jpg","png","tiff","webp"});
        targets("nef",  {"jpg","png","tiff","webp"});
        targets("arw",  {"jpg","png","tiff","webp"});
        targets("dng",  {"jpg","png","tiff","webp"});

        // Video
        targets("mp4",  {"mp3","wav","aac","webm","mkv","avi","mov","gif"});
        targets("mov",  {"mp4","mp3","wav","webm","gif"});
        targets("avi",  {"mp4","mp3","wav","webm","mkv","gif"});
        targets("mkv",  {"mp4","mp3","wav","webm","avi"});
        targets("webm", {"mp4","mp3","wav","gif"});
        targets("flv",  {"mp4","mp3","wav"});
        targets("wmv",  {"mp4","mp3","wav","webm"});
        targets("vob",  {"mp4","mkv","avi","mp3","wav"});
        targets("rmvb", {"mp4","mkv","avi","mp3","wav"});

        // Audio
        targets("mp3",  {"wav","flac","aac","ogg","opus","m4a"});
        targets("wav",  {"mp3","flac","aac","ogg","opus","m4a"});
        targets("flac", {"mp3","wav","aac","ogg","opus"});
        targets("aac",  {"mp3","wav","flac","ogg"});
        targets("ogg",  {"mp3","wav","flac","aac"});
        targets("opus", {"mp3","wav","ogg","flac"});
        targets("m4a",  {"mp3","wav","flac","aac"});
        targets("caf",  {"mp3","wav","flac","aac","ogg"});

        // 3D
        targets("fbx",  {"obj","glb","gltf","stl","dae","ply"});
        targets("obj",  {"fbx","glb","gltf","stl","dae","ply"});
        targets("glb",  {"obj","fbx","gltf","stl","dae","ply"});
        targets("gltf", {"glb","obj","fbx","stl"});
        targets("stl",  {"obj","glb","gltf","ply","dae"});
        targets("dae",  {"fbx","obj","glb","gltf","stl"});
        targets("ply",  {"obj","stl","glb","gltf"});
        targets("3ds",  {"obj","glb","gltf","stl"});

        // Data
        targets("json", {"xml","yaml","csv","toml","ini","env"});
        targets("xml",  {"json","yaml","csv"});
        targets("yaml", {"json","xml","csv","toml"});
        targets("yml",  {"json","xml","csv","toml"});
        targets("csv",  {"json","xml","yaml","tsv","ods","xlsx","xls"});
        targets("tsv",  {"csv","json"});
        targets("toml", {"json","yaml"});
        targets("ini",  {"json","yaml","toml","env"});
        targets("env",  {"json","yaml","toml","ini"});

        // Archives
        targets("zip",  {"tar","gz","bz2","xz","7z","zst","tgz","tbz2","txz","lz4","lzma"});
        targets("tar",  {"zip","gz","bz2","xz","zst","tgz","tbz2","txz","lz4","lzma"});
        targets("gz",   {"zip","tar","bz2","xz","zst","tgz","lz4","lzma"});
        targets("bz2",  {"zip","tar","gz","xz","zst","tbz2","lz4"});
        targets("xz",   {"zip","tar","gz","bz2","zst","txz","lzma"});
        targets("zst",  {"zip","tar","gz","bz2","xz","lz4"});
        targets("7z",   {"zip","tar","gz","bz2","xz","lz4"});
        targets("rar",  {"zip","tar","gz","7z","bz2","xz"});
        targets("tgz",  {"zip","tar","gz","bz2","xz","7z"});
        targets("tbz2", {"zip","tar","gz","bz2","xz","7z"});
        targets("txz",  {"zip","tar","gz","bz2","xz","7z"});
        targets("lz4",  {"zip","tar","gz","bz2","xz","zst"});
        targets("lzma", {"zip","tar","gz","xz","zst"});

        // Documents
        targets("docx", {"pdf","odt","rtf","txt","html","doc"});
        targets("doc",  {"pdf","docx","odt","rtf","txt"});
        targets("odt",  {"pdf","docx","doc","rtf","txt","html"});
        targets("rtf",  {"pdf","docx","odt","txt"});
        targets("pdf",  {"odt","txt","html","png","jpg","webp"});
        targets("xlsx", {"pdf","ods","csv","xls"});
        targets("xls",  {"pdf","xlsx","ods","csv"});
        targets("ods",  {"pdf","xlsx","xls","csv"});
        targets("pptx", {"pdf","odp","ppt"});
        targets("ppt",  {"pdf","pptx","odp"});
        targets("odp",  {"pdf","pptx","ppt"});
        targets("txt",  {"pdf","docx","odt","rtf","html"});
        targets("html", {"pdf","docx","odt","rtf","txt"});
        targets("htm",  {"pdf","docx","odt","rtf","txt"});
        targets("md",       {"pdf","docx","odt","html","rst","tex","epub"});
        targets("markdown", {"pdf","docx","odt","html","rst","tex","epub"});
        targets("rst",      {"pdf","docx","html","md"});
        targets("tex",      {"pdf","docx","html","md"});
        targets("latex",    {"pdf","docx","html","md"});

        // Ebooks
        targets("epub", {"mobi","azw3","pdf"});
        targets("mobi", {"epub","azw3","pdf"});
        targets("azw3", {"epub","mobi","pdf"});
        targets("azw",  {"epub","mobi","pdf"});
        targets("fb2",  {"epub","mobi","azw3","pdf"});
        targets("djvu", {"pdf","epub"});
        targets("lit",  {"epub","mobi","pdf"});
    }

    void reg(const std::string& ext, Category cat, const std::string& mime) {
        m_map[ext] = { ext, cat, mime };
    }

    void targets(const std::string& from, std::vector<std::string> tos) {
        for (auto& t : tos) m_targets[from].insert(t);
    }

    std::unordered_map<std::string, Format>                          m_map;
    std::unordered_map<std::string, Format>                          m_mimeMap;   // MIME → Format
    std::unordered_map<std::string, std::unordered_set<std::string>> m_targets;
};

} // namespace converter