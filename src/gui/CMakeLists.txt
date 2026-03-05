cmake_minimum_required(VERSION 3.21)

# ── Find Qt6 ──────────────────────────────────────────────────────────────────
find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Quick
    QuickControls2
    Qml
    Widgets
    Svg
)

qt_standard_project_setup()

# ── GUI executable ────────────────────────────────────────────────────────────
qt_add_executable(anyfile_gui
    main_gui.cpp
    resources/app.rc
)

# ── Embed icons and other static resources ───────────────────────────────────
qt_add_resources(anyfile_gui "gui_resources"
    PREFIX "/"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/icons/app.png
        resources/icons/app.ico
        resources/icons/emblem.svg
        resources/icons/horizontal.svg
        resources/icons/file.svg
        resources/icons/folder.svg
        resources/icons/cogwheel.svg
        resources/icons/close.svg
        resources/icons/minimize.svg
        resources/icons/expand.svg
        resources/icons/tooltip.svg
        resources/icons/dropzone.svg
        resources/icons/warning.svg
        resources/icons/image.svg
        resources/icons/video.svg
        resources/icons/audio.svg
        resources/icons/3D.svg
        resources/icons/archive.svg
        resources/icons/Data.svg
        resources/icons/documents.svg
        resources/icons/ebooks.svg
        resources/fonts/Manrope-Regular.ttf
)

# ── QML module ────────────────────────────────────────────────────────────────
qt_add_qml_module(anyfile_gui
    URI Anyfile
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/HeaderBar.qml
        qml/HeaderButton.qml
        qml/FormatBrowser.qml
        qml/FilePanel.qml
        qml/DropZone.qml
        qml/OutputZone.qml
        qml/AdvancedPanel.qml
        qml/AppScrollBar.qml
        qml/ResultPanel.qml
        qml/ProgressBar2.qml
        qml/FieldDropdown.qml
        qml/TintedIcon.qml
        qml/ToolTip.qml
    SOURCES
        ConverterBridge.h
)

# ── Link ──────────────────────────────────────────────────────────────────────
target_link_libraries(anyfile_gui PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Qml
    Qt6::Widgets
    Qt6::Svg
    converter_core
)

target_include_directories(anyfile_gui PRIVATE
    ${CMAKE_SOURCE_DIR}/src/core
)

# ── macOS app bundle ──────────────────────────────────────────────────────────
set_target_properties(anyfile_gui PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "Anyfile"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1"
    WIN32_EXECUTABLE TRUE
)

# ── Windows: deploy Qt DLLs next to the exe (requires windeployqt) ────────────
if(WIN32)
    # MSYS2 ships windeployqt as windeployqt6; fall back to windeployqt for other installs
    if(EXISTS "${Qt6_DIR}/../../../bin/windeployqt6.exe")
        set(WINDEPLOYQT_BIN "${Qt6_DIR}/../../../bin/windeployqt6.exe")
    else()
        set(WINDEPLOYQT_BIN "${Qt6_DIR}/../../../bin/windeployqt.exe")
    endif()
    add_custom_command(TARGET anyfile_gui POST_BUILD
        COMMAND "${WINDEPLOYQT_BIN}"
                --no-translations
                --no-quick-import
                "$<TARGET_FILE:anyfile_gui>"
        COMMENT "Running windeployqt..."
        VERBATIM
    )
endif()
