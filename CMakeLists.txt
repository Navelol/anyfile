cmake_minimum_required(VERSION 3.20)
project(converter VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)  # for clangd

# ── Output directories ────────────────────────────────────────────────────────
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# ── Platform detection ────────────────────────────────────────────────────────
if(WIN32)
    message(STATUS "Platform: Windows")
    add_compile_definitions(PLATFORM_WINDOWS)
elseif(APPLE)
    message(STATUS "Platform: macOS")
    add_compile_definitions(PLATFORM_MACOS)
elseif(UNIX)
    message(STATUS "Platform: Linux")
    add_compile_definitions(PLATFORM_LINUX)
endif()

# ── macOS: resolve Homebrew prefix so find_package / pkg_check_modules work ──
# Homebrew installs libraries under a prefix that CMake does not search by
# default.  On Apple Silicon the prefix is /opt/homebrew; on Intel it is
# /usr/local.  We ask Homebrew directly so both architectures are covered
# automatically without hard-coding either path.
if(APPLE)
    execute_process(
        COMMAND brew --prefix
        OUTPUT_VARIABLE HOMEBREW_PREFIX
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(HOMEBREW_PREFIX)
        message(STATUS "Homebrew prefix: ${HOMEBREW_PREFIX}")
        list(PREPEND CMAKE_PREFIX_PATH "${HOMEBREW_PREFIX}")
        # Make pkg-config aware of Homebrew .pc files so pkg_check_modules
        # can find FFmpeg, libarchive, etc. without extra -L/-I flags.
        set(ENV{PKG_CONFIG_PATH}
            "${HOMEBREW_PREFIX}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
        # Point CMake directly at the Homebrew pkg-config binary so
        # find_package(PkgConfig) succeeds even when /opt/homebrew/bin is
        # not yet on the shell PATH (common when invoking cmake directly
        # rather than through build_macos.sh).
        set(PKG_CONFIG_EXECUTABLE "${HOMEBREW_PREFIX}/bin/pkg-config"
            CACHE FILEPATH "pkg-config from Homebrew" FORCE)
        # Several Homebrew formulae are "keg-only" — they conflict with macOS
        # system libraries so Homebrew does not symlink them into the main
        # prefix.  Their headers and cmake configs live under
        # /opt/homebrew/opt/<name>/ instead.  Add each keg-only path
        # explicitly so find_package() can locate them.
        foreach(_keg libarchive)
            list(APPEND CMAKE_PREFIX_PATH "${HOMEBREW_PREFIX}/opt/${_keg}")
            set(ENV{PKG_CONFIG_PATH}
                "${HOMEBREW_PREFIX}/opt/${_keg}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
        endforeach()
    else()
        message(WARNING
            "Homebrew not found. Dependencies may not be located automatically. "
            "Install Homebrew (https://brew.sh) or set CMAKE_PREFIX_PATH manually.")
    endif()
endif()

# ── Dependencies via PkgConfig ────────────────────────────────────────────────
find_package(PkgConfig REQUIRED)

# FFmpeg — IMPORTED_TARGET creates PkgConfig::AV* targets that carry both
# include directories and library search paths (-L/opt/homebrew/lib on macOS),
# which is required for the linker to find Homebrew-installed dylibs.
pkg_check_modules(AVCODEC    REQUIRED IMPORTED_TARGET libavcodec)
pkg_check_modules(AVFORMAT   REQUIRED IMPORTED_TARGET libavformat)
pkg_check_modules(AVUTIL     REQUIRED IMPORTED_TARGET libavutil)
pkg_check_modules(SWSCALE    REQUIRED IMPORTED_TARGET libswscale)
pkg_check_modules(SWRESAMPLE REQUIRED IMPORTED_TARGET libswresample)

# Assimp
find_package(assimp REQUIRED)

# libarchive
find_package(LibArchive REQUIRED)

# nlohmann-json (header-only, via submodule)
add_subdirectory(thirdparty/nlohmann-json)

# GUI — optional, requires Qt6
option(BUILD_GUI   "Build the Qt6 GUI frontend"       OFF)
option(BUILD_TESTS "Build the Catch2 unit test suite" ON)

# ── Subdirectories ────────────────────────────────────────────────────────────
add_subdirectory(src/core)
add_subdirectory(src/cli)

if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(BUILD_GUI)
    find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Qml Widgets Svg)
    add_subdirectory(src/gui)
endif()

message(STATUS "")
message(STATUS "┌─ Converter Build Config ─────────────────┐")
message(STATUS "│  C++ Standard : ${CMAKE_CXX_STANDARD}")
message(STATUS "│  Build type   : ${CMAKE_BUILD_TYPE}")
message(STATUS "│  Build GUI    : ${BUILD_GUI}")
message(STATUS "│  Build tests  : ${BUILD_TESTS}")
message(STATUS "│  FFmpeg       : ${AVCODEC_VERSION}")
message(STATUS "│  Assimp       : ${assimp_VERSION}")
message(STATUS "│  nlohmann-json: submodule             │")
message(STATUS "└──────────────────────────────────────────┘")
message(STATUS "")

# ── CMPack ────────────────────────────────────────────────────────────
include(CPack)
set(CPACK_GENERATOR "ZIP;NSIS;TGZ;DEB")
set(CPACK_PACKAGE_NAME "everyfile")
set(CPACK_PACKAGE_VERSION_MAJOR 1)