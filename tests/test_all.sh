#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
#  anyfile — comprehensive conversion test suite
# ─────────────────────────────────────────────────────────────────────────────

REPO="/mnt/z/Repositories/C++/everyfile"
BIN="$REPO/build/linux/bin/anyfile"
TESTS="$REPO/tests"
OUT="$TESTS/test_output"

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

PASS=0
FAIL=0
SKIP=0

rm -rf "$OUT"
mkdir -p "$OUT"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

run_test() {
    local desc="$1"
    local input="$2"
    local output="$3"

    if [ ! -f "$input" ]; then
        echo -e "  ${YELLOW}SKIP${RESET}  $desc  (no input file)"
        ((SKIP++))
        return
    fi

    "$BIN" "$input" "$output" > /dev/null 2>&1

    if [ $? -eq 0 ] && [ -f "$output" ] && [ -s "$output" ]; then
        echo -e "  ${GREEN}PASS${RESET}  $desc"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RESET}  $desc"
        ((FAIL++))
    fi
}

# Variant of run_test that passes extra flags to the binary
run_test_flags() {
    local desc="$1"
    local input="$2"
    local output="$3"
    shift 3
    local flags="$@"

    if [ ! -f "$input" ] && [ ! -d "$input" ]; then
        echo -e "  ${YELLOW}SKIP${RESET}  $desc  (no input)"
        ((SKIP++))
        return
    fi

    "$BIN" "$input" "$output" $flags > /dev/null 2>&1

    if [ $? -eq 0 ] && [ -f "$output" ] && [ -s "$output" ]; then
        echo -e "  ${GREEN}PASS${RESET}  $desc"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RESET}  $desc"
        ((FAIL++))
    fi
}

# Batch test — checks that output directory was created and has files
run_batch_test() {
    local desc="$1"
    local input_dir="$2"
    local format_arg="$3"
    local output_dir="$4"
    shift 4
    local flags="$@"

    if [ ! -d "$input_dir" ] || [ -z "$(ls -A "$input_dir" 2>/dev/null)" ]; then
        echo -e "  ${YELLOW}SKIP${RESET}  $desc  (no input dir or empty)"
        ((SKIP++))
        return
    fi

    "$BIN" "$input_dir" "$format_arg" "$output_dir" $flags > /dev/null 2>&1

    if [ -d "$output_dir" ] && [ "$(ls -A "$output_dir" 2>/dev/null)" ]; then
        echo -e "  ${GREEN}PASS${RESET}  $desc"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RESET}  $desc"
        ((FAIL++))
    fi
}

section() {
    echo ""
    echo -e "${CYAN}${BOLD}── $1 ─────────────────────────────────────────${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Create seed files
# ─────────────────────────────────────────────────────────────────────────────

section "Setting up seed files"

# Data
mkdir -p "$OUT/data"
echo '{"name":"Alice","age":30,"city":"Tampa"}' > "$OUT/data/seed.json"
echo -e "name,age,city\nAlice,30,Tampa\nBob,25,Orlando" > "$OUT/data/seed.csv"
cat > "$OUT/data/seed.yaml" << 'EOF'
- name: Alice
  age: 30
  city: Tampa
- name: Bob
  age: 25
  city: Orlando
EOF
printf '<root><n>Alice</n><age>30</age></root>' > "$OUT/data/seed.xml"
printf 'name = "Alice"\nage = 30\ncity = "Tampa"\n' > "$OUT/data/seed.toml"

# Archives
mkdir -p "$OUT/archives/seed_dir"
echo "hello everyfile" > "$OUT/archives/seed_dir/hello.txt"
echo "foo bar baz"     > "$OUT/archives/seed_dir/foo.txt"
cd "$OUT/archives" && zip -r seed.zip seed_dir/ > /dev/null 2>&1
cd "$REPO"

# Documents
mkdir -p "$OUT/documents"
echo "Hello from anyfile" > "$OUT/documents/seed.txt"
echo "# Hello\n\nThis is **markdown**." > "$OUT/documents/seed.md"
echo "<html><body><h1>Hello</h1><p>anyfile test</p></body></html>" > "$OUT/documents/seed.html"

# INI / ENV
cat > "$OUT/data/seed.ini" << 'EOF'
[user]
name = Alice
age = 30
city = Tampa
EOF

cat > "$OUT/data/seed.env" << 'EOF'
NAME="Alice"
AGE=30
CITY="Tampa"
EOF

# Copy real test files if they exist
[ -f "$TESTS/data/people.json" ]       && cp "$TESTS/data/people.json"       "$OUT/data/people.json"
[ -f "$TESTS/documents/test.docx" ]    && cp "$TESTS/documents/test.docx"    "$OUT/documents/seed.docx"
[ -f "$TESTS/documents/test.xlsx" ]    && cp "$TESTS/documents/test.xlsx"    "$OUT/documents/seed.xlsx"
[ -f "$TESTS/documents/test.odt" ]     && cp "$TESTS/documents/test.odt"     "$OUT/documents/seed.odt"
[ -f "$TESTS/documents/test.pptx" ]    && cp "$TESTS/documents/test.pptx"    "$OUT/documents/seed.pptx"
[ -f "$TESTS/documents/test.pdf" ]     && cp "$TESTS/documents/test.pdf"     "$OUT/documents/seed.pdf"
[ -f "$TESTS/ebooks/test.epub" ]       && cp "$TESTS/ebooks/test.epub"       "$OUT/ebooks/seed.epub"
[ -f "$TESTS/ebooks/test.mobi" ]       && cp "$TESTS/ebooks/test.mobi"       "$OUT/ebooks/seed.mobi"
[ -f "$TESTS/images/test.png" ]        && cp "$TESTS/images/test.png"        "$OUT/images/seed.png"
[ -f "$TESTS/audio/test.mp3" ]         && cp "$TESTS/audio/test.mp3"         "$OUT/audio/seed.mp3"
[ -f "$TESTS/models/seed.obj" ]        && cp "$TESTS/models/seed.obj"        "$OUT/models/seed.obj"
[ -f "$TESTS/models/seed.fbx" ]        && cp "$TESTS/models/seed.fbx"        "$OUT/models/seed.fbx"
[ -f "$TESTS/models/seed.stl" ]        && cp "$TESTS/models/seed.stl"        "$OUT/models/seed.stl"
[ -f "$TESTS/video/test.avi" ]         && cp "$TESTS/video/test.avi"         "$OUT/video/seed.avi"
[ -f "$TESTS/video/test.mp4" ]         && cp "$TESTS/video/test.mp4"         "$OUT/video/seed.mp4"

mkdir -p "$OUT/images" "$OUT/audio" "$OUT/video" "$OUT/models" "$OUT/ebooks" "$OUT/batch"

echo -e "  ${GREEN}Done${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# DATA FORMATS
# ─────────────────────────────────────────────────────────────────────────────

section "Data Formats"

run_test "JSON → XML"   "$OUT/data/seed.json"  "$OUT/data/out.xml"
run_test "JSON → YAML"  "$OUT/data/seed.json"  "$OUT/data/out.yaml"
run_test "JSON → CSV"   "$OUT/data/people.json" "$OUT/data/out.csv"
run_test "JSON → TOML"  "$OUT/data/seed.json"  "$OUT/data/out.toml"
run_test "JSON → INI"   "$OUT/data/seed.json"  "$OUT/data/out.ini"
run_test "JSON → ENV"   "$OUT/data/seed.json"  "$OUT/data/out.env"
run_test "XML  → JSON"  "$OUT/data/seed.xml"   "$OUT/data/from_xml.json"
run_test "XML  → YAML"  "$OUT/data/seed.xml"   "$OUT/data/from_xml.yaml"
run_test "YAML → JSON"  "$OUT/data/seed.yaml"  "$OUT/data/from_yaml.json"
run_test "YAML → XML"   "$OUT/data/seed.yaml"  "$OUT/data/from_yaml.xml"
run_test "YAML → CSV"   "$OUT/data/seed.yaml"  "$OUT/data/from_yaml.csv"
run_test "CSV  → JSON"  "$OUT/data/seed.csv"   "$OUT/data/from_csv.json"
run_test "CSV  → XML"   "$OUT/data/seed.csv"   "$OUT/data/from_csv.xml"
run_test "CSV  → YAML"  "$OUT/data/seed.csv"   "$OUT/data/from_csv.yaml"
run_test "CSV  → TSV"   "$OUT/data/seed.csv"   "$OUT/data/from_csv.tsv"
run_test "TOML → JSON"  "$OUT/data/seed.toml"  "$OUT/data/from_toml.json"
run_test "TOML → YAML"  "$OUT/data/seed.toml"  "$OUT/data/from_toml.yaml"
run_test "INI  → JSON"  "$OUT/data/seed.ini"   "$OUT/data/from_ini.json"
run_test "INI  → YAML"  "$OUT/data/seed.ini"   "$OUT/data/from_ini.yaml"
run_test "ENV  → JSON"  "$OUT/data/seed.env"   "$OUT/data/from_env.json"
run_test "ENV  → TOML"  "$OUT/data/seed.env"   "$OUT/data/from_env.toml"

# ─────────────────────────────────────────────────────────────────────────────
# ARCHIVES
# ─────────────────────────────────────────────────────────────────────────────

section "Archives"

run_test "ZIP  → TAR"   "$OUT/archives/seed.zip"  "$OUT/archives/out.tar"
run_test "ZIP  → GZ"    "$OUT/archives/seed.zip"  "$OUT/archives/out.gz"
run_test "ZIP  → BZ2"   "$OUT/archives/seed.zip"  "$OUT/archives/out.bz2"
run_test "ZIP  → XZ"    "$OUT/archives/seed.zip"  "$OUT/archives/out.xz"
run_test "ZIP  → 7Z"    "$OUT/archives/seed.zip"  "$OUT/archives/out.7z"
run_test "ZIP  → ZST"   "$OUT/archives/seed.zip"  "$OUT/archives/out.zst"
run_test "ZIP  → TGZ"   "$OUT/archives/seed.zip"  "$OUT/archives/out.tgz"
run_test "ZIP  → TBZ2"  "$OUT/archives/seed.zip"  "$OUT/archives/out.tbz2"
run_test "ZIP  → TXZ"   "$OUT/archives/seed.zip"  "$OUT/archives/out.txz"
run_test "ZIP  → LZ4"   "$OUT/archives/seed.zip"  "$OUT/archives/out.lz4"
run_test "ZIP  → LZMA"  "$OUT/archives/seed.zip"  "$OUT/archives/out.lzma"
run_test "7Z   → ZIP"   "$OUT/archives/out.7z"    "$OUT/archives/from_7z.zip"
run_test "TGZ  → ZIP"   "$OUT/archives/out.tgz"   "$OUT/archives/from_tgz.zip"
run_test "BZ2  → ZIP"   "$OUT/archives/out.bz2"   "$OUT/archives/from_bz2.zip"
run_test "XZ   → ZIP"   "$OUT/archives/out.xz"    "$OUT/archives/from_xz.zip"

# ─────────────────────────────────────────────────────────────────────────────
# DOCUMENTS
# ─────────────────────────────────────────────────────────────────────────────

section "Documents"

run_test "TXT  → PDF"   "$OUT/documents/seed.txt"   "$OUT/documents/from_txt.pdf"
run_test "TXT  → DOCX"  "$OUT/documents/seed.txt"   "$OUT/documents/from_txt.docx"
run_test "TXT  → ODT"   "$OUT/documents/seed.txt"   "$OUT/documents/from_txt.odt"
run_test "TXT  → HTML"  "$OUT/documents/seed.txt"   "$OUT/documents/from_txt.html"
run_test "MD   → PDF"   "$OUT/documents/seed.md"    "$OUT/documents/from_md.pdf"
run_test "MD   → DOCX"  "$OUT/documents/seed.md"    "$OUT/documents/from_md.docx"
run_test "MD   → HTML"  "$OUT/documents/seed.md"    "$OUT/documents/from_md.html"
run_test "MD   → ODT"   "$OUT/documents/seed.md"    "$OUT/documents/from_md.odt"
run_test "HTML → PDF"   "$OUT/documents/seed.html"  "$OUT/documents/from_html.pdf"
run_test "HTML → DOCX"  "$OUT/documents/seed.html"  "$OUT/documents/from_html.docx"
run_test "HTML → ODT"   "$OUT/documents/seed.html"  "$OUT/documents/from_html.odt"
run_test "DOCX → PDF"   "$OUT/documents/seed.docx"  "$OUT/documents/from_docx.pdf"
run_test "DOCX → ODT"   "$OUT/documents/seed.docx"  "$OUT/documents/from_docx.odt"
run_test "DOCX → RTF"   "$OUT/documents/seed.docx"  "$OUT/documents/from_docx.rtf"
run_test "DOCX → TXT"   "$OUT/documents/seed.docx"  "$OUT/documents/from_docx.txt"
run_test "ODT  → PDF"   "$OUT/documents/seed.odt"   "$OUT/documents/from_odt.pdf"
run_test "ODT  → DOCX"  "$OUT/documents/seed.odt"   "$OUT/documents/from_odt.docx"
run_test "XLSX → PDF"   "$OUT/documents/seed.xlsx"  "$OUT/documents/from_xlsx.pdf"
run_test "XLSX → ODS"   "$OUT/documents/seed.xlsx"  "$OUT/documents/from_xlsx.ods"
run_test "XLSX → CSV"   "$OUT/documents/seed.xlsx"  "$OUT/documents/from_xlsx.csv"
run_test "ODS  → XLSX"  "$OUT/documents/from_xlsx.ods"  "$OUT/documents/from_ods.xlsx"
run_test "PPTX → PDF"   "$OUT/documents/seed.pptx"  "$OUT/documents/from_pptx.pdf"
run_test "PPTX → ODP"   "$OUT/documents/seed.pptx"  "$OUT/documents/from_pptx.odp"
run_test "CSV  → ODS"   "$OUT/data/seed.csv"        "$OUT/documents/from_csv.ods"
run_test "CSV  → XLSX"  "$OUT/data/seed.csv"        "$OUT/documents/from_csv.xlsx"

# ─────────────────────────────────────────────────────────────────────────────
# PDF → IMAGE (cross-category)
# ─────────────────────────────────────────────────────────────────────────────

section "PDF → Image"

# PDF → image bundles pages into a zip; pass the image ext and the binary renames to .zip
for _ext in png jpg; do
    _desc="PDF  → ${_ext^^} (zip)"
    _in="$OUT/documents/seed.pdf"
    _arg="$OUT/documents/from_pdf_${_ext}.${_ext}"
    _out="$OUT/documents/from_pdf_${_ext}.zip"
    if [ ! -f "$_in" ]; then
        echo -e "  ${YELLOW}SKIP${RESET}  $_desc  (no input file)"
        ((SKIP++))
    else
        "$BIN" "$_in" "$_arg" > /dev/null 2>&1
        if [ -f "$_out" ] && [ -s "$_out" ]; then
            echo -e "  ${GREEN}PASS${RESET}  $_desc"
            ((PASS++))
        else
            echo -e "  ${RED}FAIL${RESET}  $_desc"
            ((FAIL++))
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# EBOOKS
# ─────────────────────────────────────────────────────────────────────────────

section "Ebooks"

run_test "EPUB → MOBI"  "$OUT/ebooks/seed.epub"  "$OUT/ebooks/out.mobi"
run_test "EPUB → AZW3"  "$OUT/ebooks/seed.epub"  "$OUT/ebooks/out.azw3"
run_test "EPUB → PDF"   "$OUT/ebooks/seed.epub"  "$OUT/ebooks/out.pdf"
run_test "MOBI → EPUB"  "$OUT/ebooks/seed.mobi"  "$OUT/ebooks/from_mobi.epub"
run_test "MOBI → AZW3"  "$OUT/ebooks/seed.mobi"  "$OUT/ebooks/from_mobi.azw3"
run_test "FB2  → EPUB"  "$OUT/ebooks/seed.fb2"   "$OUT/ebooks/from_fb2.epub"
run_test "DJVU → PDF"   "$OUT/ebooks/seed.djvu"  "$OUT/ebooks/from_djvu.pdf"

# ─────────────────────────────────────────────────────────────────────────────
# IMAGES
# ─────────────────────────────────────────────────────────────────────────────

section "Images"

run_test "PNG  → JPG"   "$OUT/images/seed.png"  "$OUT/images/out.jpg"
run_test "PNG  → WEBP"  "$OUT/images/seed.png"  "$OUT/images/out.webp"
run_test "PNG  → BMP"   "$OUT/images/seed.png"  "$OUT/images/out.bmp"
run_test "PNG  → TIFF"  "$OUT/images/seed.png"  "$OUT/images/out.tiff"
run_test "PNG  → GIF"   "$OUT/images/seed.png"  "$OUT/images/out.gif"
run_test "PNG  → AVIF"  "$OUT/images/seed.png"  "$OUT/images/out.avif"
run_test "JPG  → PNG"   "$OUT/images/out.jpg"   "$OUT/images/from_jpg.png"
run_test "WEBP → PNG"   "$OUT/images/out.webp"  "$OUT/images/from_webp.png"

# ─────────────────────────────────────────────────────────────────────────────
# AUDIO
# ─────────────────────────────────────────────────────────────────────────────

section "Audio"

run_test "MP3  → WAV"   "$OUT/audio/seed.mp3"  "$OUT/audio/out.wav"
run_test "MP3  → FLAC"  "$OUT/audio/seed.mp3"  "$OUT/audio/out.flac"
run_test "MP3  → AAC"   "$OUT/audio/seed.mp3"  "$OUT/audio/out.aac"
run_test "MP3  → OGG"   "$OUT/audio/seed.mp3"  "$OUT/audio/out.ogg"
run_test "MP3  → OPUS"  "$OUT/audio/seed.mp3"  "$OUT/audio/out.opus"
run_test "WAV  → MP3"   "$OUT/audio/out.wav"   "$OUT/audio/from_wav.mp3"
run_test "FLAC → MP3"   "$OUT/audio/out.flac"  "$OUT/audio/from_flac.mp3"

# ─────────────────────────────────────────────────────────────────────────────
# VIDEO
# ─────────────────────────────────────────────────────────────────────────────

section "Video"

run_test "AVI  → MP4"   "$OUT/video/seed.avi"  "$OUT/video/from_avi.mp4"
run_test "AVI  → MKV"   "$OUT/video/seed.avi"  "$OUT/video/from_avi.mkv"
run_test "AVI  → WEBM"  "$OUT/video/seed.avi"  "$OUT/video/from_avi.webm"
run_test "AVI  → MP3"   "$OUT/video/seed.avi"  "$OUT/video/from_avi.mp3"
run_test "AVI  → GIF"   "$OUT/video/seed.avi"  "$OUT/video/from_avi.gif"
run_test "MP4  → MKV"   "$OUT/video/seed.mp4"  "$OUT/video/from_mp4.mkv"
run_test "MP4  → MP3"   "$OUT/video/seed.mp4"  "$OUT/video/from_mp4.mp3"
run_test "MP4  → GIF"   "$OUT/video/seed.mp4"  "$OUT/video/from_mp4.gif"

# ─────────────────────────────────────────────────────────────────────────────
# MEDIA ENCODING FLAGS
# ─────────────────────────────────────────────────────────────────────────────

section "Media Encoding Flags"

run_test_flags "AVI → MP4 (libx265 --crf 28)"  "$OUT/video/seed.avi"   "$OUT/video/from_avi_x265.mp4"   --video-codec libx265 --crf 28
run_test_flags "AVI → MP4 (720p)"              "$OUT/video/seed.avi"   "$OUT/video/from_avi_720p.mp4"   --resolution 1280x720
run_test_flags "AVI → MP4 (30fps)"             "$OUT/video/seed.avi"   "$OUT/video/from_avi_30fps.mp4"  --framerate 30
run_test_flags "MP3 re-encode (320k)"          "$OUT/audio/seed.mp3"   "$OUT/audio/seed_320k.mp3"       --audio-bitrate 320k --f
run_test_flags "AVI → MP3 (libmp3lame 192k)"   "$OUT/video/seed.avi"   "$OUT/video/from_avi_192k.mp3"   --audio-codec libmp3lame --audio-bitrate 192k

# ─────────────────────────────────────────────────────────────────────────────
# 3D MODELS
# ─────────────────────────────────────────────────────────────────────────────

section "3D Models"

run_test "OBJ  → GLB"   "$OUT/models/seed.obj"  "$OUT/models/out.glb"
run_test "OBJ  → STL"   "$OUT/models/seed.obj"  "$OUT/models/out.stl"
run_test "OBJ  → DAE"   "$OUT/models/seed.obj"  "$OUT/models/out.dae"
run_test "OBJ  → PLY"   "$OUT/models/seed.obj"  "$OUT/models/out.ply"
run_test "OBJ  → GLTF"  "$OUT/models/seed.obj"  "$OUT/models/out.gltf"
run_test "GLB  → OBJ"   "$OUT/models/out.glb"   "$OUT/models/from_glb.obj"
run_test "STL  → OBJ"   "$OUT/models/out.stl"   "$OUT/models/from_stl.obj"
run_test "FBX  → OBJ"   "$OUT/models/seed.fbx"  "$OUT/models/from_fbx.obj"
run_test "FBX  → GLB"   "$OUT/models/seed.fbx"  "$OUT/models/from_fbx.glb"
run_test "FBX  → STL"   "$OUT/models/seed.fbx"  "$OUT/models/from_fbx.stl"
run_test "STL  → GLB"   "$OUT/models/seed.stl"  "$OUT/models/from_stl.glb"
run_test "STL  → OBJ"   "$OUT/models/seed.stl"  "$OUT/models/from_stl2.obj"

# ─────────────────────────────────────────────────────────────────────────────
# BATCH MODE
# ─────────────────────────────────────────────────────────────────────────────

section "Batch Mode"

# Simple batch — convert all audio to wav
run_batch_test "Batch audio → wav"          "$OUT/audio"  "mp3:wav,flac:wav"  "$OUT/batch/audio_wav"

# Batch with explicit output dir
run_batch_test "Batch audio → mp3 (explicit out)" "$OUT/audio" "wav:mp3" "$OUT/batch/audio_mp3"

# Batch video → mp3 (extract audio)
run_batch_test "Batch video → mp3"          "$OUT/video"  "avi:mp3,mp4:mp3"   "$OUT/batch/video_audio"

# ─────────────────────────────────────────────────────────────────────────────
# SINGLE FILE — NEW SYNTAX
# ─────────────────────────────────────────────────────────────────────────────

section "Single File — New Syntax"

# Auto-named output
if [ -f "$OUT/audio/seed.mp3" ]; then
    "$BIN" "$OUT/audio/seed.mp3" flac > /dev/null 2>&1
    if [ -f "$OUT/audio/seed.flac" ] && [ -s "$OUT/audio/seed.flac" ]; then
        echo -e "  ${GREEN}PASS${RESET}  Auto-named: MP3 → seed.flac"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RESET}  Auto-named: MP3 → seed.flac"
        ((FAIL++))
    fi
else
    echo -e "  ${YELLOW}SKIP${RESET}  Auto-named: MP3 → seed.flac  (no input)"
    ((SKIP++))
fi

# Conflict detection — run same conversion twice, second should fail (exit 1)
if [ -f "$OUT/audio/seed.mp3" ]; then
    "$BIN" "$OUT/audio/seed.mp3" "$OUT/audio/conflict_test.ogg" > /dev/null 2>&1
    "$BIN" "$OUT/audio/seed.mp3" "$OUT/audio/conflict_test.ogg" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "  ${GREEN}PASS${RESET}  Conflict detection: second run blocked"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RESET}  Conflict detection: should have been blocked"
        ((FAIL++))
    fi
else
    echo -e "  ${YELLOW}SKIP${RESET}  Conflict detection  (no input)"
    ((SKIP++))
fi

# --f overwrite
if [ -f "$OUT/audio/seed.mp3" ]; then
    "$BIN" "$OUT/audio/seed.mp3" "$OUT/audio/conflict_test.ogg" --f > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}PASS${RESET}  Force overwrite (--f)"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RESET}  Force overwrite (--f)"
        ((FAIL++))
    fi
else
    echo -e "  ${YELLOW}SKIP${RESET}  Force overwrite  (no input)"
    ((SKIP++))
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo -e "${BOLD}────────────────────────────────────────────────${RESET}"
echo -e "${BOLD}  Results: $TOTAL tests${RESET}"
echo -e "  ${GREEN}PASS${RESET}  $PASS"
echo -e "  ${RED}FAIL${RESET}  $FAIL"
echo -e "  ${YELLOW}SKIP${RESET}  $SKIP  (missing input files)"
echo -e "${BOLD}────────────────────────────────────────────────${RESET}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  All tests passed!${RESET}"
else
    echo -e "${RED}${BOLD}  $FAIL test(s) failed.${RESET}"
fi
echo ""