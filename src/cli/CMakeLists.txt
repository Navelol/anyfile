add_executable(anyfile main.cpp)

target_link_libraries(anyfile PRIVATE converter_core)

target_include_directories(anyfile PRIVATE
    ${CMAKE_SOURCE_DIR}/src/core
)