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
)