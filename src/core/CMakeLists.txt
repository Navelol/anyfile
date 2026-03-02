add_library(converter_core STATIC core.cpp)

set_target_properties(converter_core PROPERTIES LINKER_LANGUAGE CXX)

target_include_directories(converter_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${AVCODEC_INCLUDE_DIRS}
    ${AVFORMAT_INCLUDE_DIRS}
    ${AVUTIL_INCLUDE_DIRS}
    ${SWSCALE_INCLUDE_DIRS}
    ${SWRESAMPLE_INCLUDE_DIRS}
)

target_link_libraries(converter_core PUBLIC
    ${AVCODEC_LIBRARIES}
    ${AVFORMAT_LIBRARIES}
    ${AVUTIL_LIBRARIES}
    ${SWSCALE_LIBRARIES}
    ${SWRESAMPLE_LIBRARIES}
    assimp::assimp
    nlohmann_json::nlohmann_json
    LibArchive::LibArchive
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(MAGIC libmagic)

if(MAGIC_FOUND)
    target_compile_definitions(converter_core PRIVATE)  # __has_include handles it
    target_include_directories(converter_core PRIVATE ${MAGIC_INCLUDE_DIRS})
    target_link_libraries(converter_core PUBLIC ${MAGIC_LIBRARIES})
endif()