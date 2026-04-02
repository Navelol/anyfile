# ── Unit tests ────────────────────────────────────────────────────────────────
# Catch2 - try to find installed version, fall back to FetchContent
# Run:      cd build && ctest --output-on-failure
#           or directly: ./bin/anyfile_tests

find_package(Catch2 3.4.0 QUIET)
if(NOT Catch2_FOUND)
    message(STATUS "Catch2 not found, fetching from GitHub...")
    include(FetchContent)
    FetchContent_Declare(catch2
        GIT_REPOSITORY https://github.com/catchorg/Catch2.git
        GIT_TAG v3.4.0
    )
    FetchContent_MakeAvailable(catch2)
else()
    message(STATUS "Using system Catch2")
endif()

add_executable(anyfile_tests
    test_format_registry.cpp
    test_process.cpp
    test_dispatcher.cpp
)

target_link_libraries(anyfile_tests PRIVATE
    converter_core
    Catch2::Catch2WithMain
)

target_include_directories(anyfile_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src/core
)

# Register with CTest so `ctest` picks them up
include(CTest)
include(Catch)
catch_discover_tests(anyfile_tests)
