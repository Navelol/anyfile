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
elseif(UNIX AND NOT APPLE)
    message(STATUS "Platform: Linux")
    add_compile_definitions(PLATFORM_LINUX)
endif()

# ── Dependencies via PkgConfig ────────────────────────────────────────────────
find_package(PkgConfig REQUIRED)

# FFmpeg
pkg_check_modules(AVCODEC  REQUIRED libavcodec)
pkg_check_modules(AVFORMAT REQUIRED libavformat)
pkg_check_modules(AVUTIL   REQUIRED libavutil)
pkg_check_modules(SWSCALE  REQUIRED libswscale)
pkg_check_modules(SWRESAMPLE REQUIRED libswresample)

# Assimp
find_package(assimp REQUIRED)

# ── Subdirectories ────────────────────────────────────────────────────────────
add_subdirectory(src/core)
add_subdirectory(src/cli)

# GUI — optional, requires Qt6
option(BUILD_GUI "Build the Qt6 GUI frontend" OFF)
if(BUILD_GUI)
    find_package(Qt6 REQUIRED COMPONENTS Core Widgets)
    add_subdirectory(gui)
endif()

message(STATUS "")
message(STATUS "┌─ Converter Build Config ─────────────────┐")
message(STATUS "│  C++ Standard : ${CMAKE_CXX_STANDARD}")
message(STATUS "│  Build type   : ${CMAKE_BUILD_TYPE}")
message(STATUS "│  Build GUI    : ${BUILD_GUI}")
message(STATUS "│  FFmpeg       : ${AVCODEC_VERSION}")
message(STATUS "│  Assimp       : ${assimp_VERSION}")
message(STATUS "└──────────────────────────────────────────┘")
message(STATUS "")
