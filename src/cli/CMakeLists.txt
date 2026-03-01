add_executable(converter main.cpp)

target_link_libraries(converter PRIVATE converter_core)

target_include_directories(converter PRIVATE
    ${CMAKE_SOURCE_DIR}/src/core
)