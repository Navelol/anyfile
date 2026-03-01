#pragma once

#include "Types.h"
#include <unordered_map>
#include <unordered_set>

namespace converter {

class FormatRegistry {
public:
    static FormatRegistry& instance() {
        static FormatRegistry reg;
        return reg;
    }

    // Detect format from file extension
    std::optional<Format> detect(const fs::path& path) const {
        auto ext = path.extension().string();
        if (ext.empty()) return std::nullopt;

        // strip the dot, lowercase
        std::string key = ext.substr(1);
        for (auto& c : key) c = std::tolower(c);

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

        // ── Documents ─────────────────────────────────────────────────────────────
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

        // ── Ebooks ────────────────────────────────────────────────────────────────
        reg("epub", Category::Ebook, "application/epub+zip");
        reg("mobi", Category::Ebook, "application/x-mobipocket-ebook");
        reg("azw3", Category::Ebook, "application/vnd.amazon.ebook");
        reg("azw",  Category::Ebook, "application/vnd.amazon.ebook");

        // ── Conversion target map ─────────────────────────────────────────────
        // Images
        targets("png",  {"jpg","webp","bmp","tiff","gif","avif","tga"});
        targets("jpg",  {"png","webp","bmp","tiff","gif","avif"});
        targets("jpeg", {"png","webp","bmp","tiff","gif","avif"});
        targets("webp", {"png","jpg","bmp","tiff","gif"});
        targets("bmp",  {"png","jpg","webp","tiff"});
        targets("tiff", {"png","jpg","webp","bmp"});
        targets("gif",  {"png","jpg","webp","mp4","webm"});
        targets("heic", {"png","jpg","webp"});
        targets("avif", {"png","jpg","webp"});
        targets("tga",  {"png","jpg","webp","bmp"});
        targets("svg",  {"png","jpg","webp"});

        // Video
        targets("mp4",  {"mp3","wav","aac","webm","mkv","avi","mov","gif"});
        targets("mov",  {"mp4","mp3","wav","webm","gif"});
        targets("avi",  {"mp4","mp3","wav","webm","mkv"});
        targets("mkv",  {"mp4","mp3","wav","webm","avi"});
        targets("webm", {"mp4","mp3","wav","gif"});
        targets("flv",  {"mp4","mp3","wav"});
        targets("wmv",  {"mp4","mp3","wav","webm"});

        // Audio
        targets("mp3",  {"wav","flac","aac","ogg","opus","m4a"});
        targets("wav",  {"mp3","flac","aac","ogg","opus","m4a"});
        targets("flac", {"mp3","wav","aac","ogg","opus"});
        targets("aac",  {"mp3","wav","flac","ogg"});
        targets("ogg",  {"mp3","wav","flac","aac"});
        targets("opus", {"mp3","wav","ogg","flac"});
        targets("m4a",  {"mp3","wav","flac","aac"});

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
        targets("json", {"xml","yaml","csv","toml"});
        targets("xml",  {"json","yaml","csv"});
        targets("yaml", {"json","xml","csv","toml"});
        targets("yml",  {"json","xml","csv","toml"});
        targets("csv",  {"json","xml","yaml","tsv","ods","xlsx","xls"});
        targets("tsv",  {"csv","json"});
        targets("toml", {"json","yaml"});

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
        targets("pdf",  {"odt","txt","html"});
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
    }

    void reg(const std::string& ext, Category cat, const std::string& mime) {
        m_map[ext] = { ext, cat, mime };
    }

    void targets(const std::string& from, std::vector<std::string> tos) {
        for (auto& t : tos) m_targets[from].insert(t);
    }

    std::unordered_map<std::string, Format>                     m_map;
    std::unordered_map<std::string, std::unordered_set<std::string>> m_targets;
};

} // namespace converter
