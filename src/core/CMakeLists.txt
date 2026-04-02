add_library(converter_core STATIC core.cpp)

set_target_properties(converter_core PROPERTIES LINKER_LANGUAGE CXX)

# PkgConfig::AV* imported targets carry include dirs AND linker search paths,
# so no explicit target_include_directories for FFmpeg is needed here.
target_include_directories(converter_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(converter_core PUBLIC
    PkgConfig::AVCODEC
    PkgConfig::AVFORMAT
    PkgConfig::AVUTIL
    PkgConfig::SWSCALE
    PkgConfig::SWRESAMPLE
    assimp::assimp
    nlohmann_json::nlohmann_json
    LibArchive::LibArchive
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(MAGIC IMPORTED_TARGET libmagic)

if(MAGIC_FOUND)
    target_include_directories(converter_core PRIVATE ${MAGIC_INCLUDE_DIRS})
    target_link_libraries(converter_core PUBLIC PkgConfig::MAGIC)
endif()
