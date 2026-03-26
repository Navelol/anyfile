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
# Platform-specific resource files:
#   Windows — app.rc embeds the app icon and PE version metadata.
#   macOS   — app.icns is embedded into the .app bundle by CMake.
#             Generate it from resources/icons/app.png via build_macos.sh
#             (uses sips + iconutil) before running CMake.
#   Linux   — no binary resource file needed; icons are installed separately.
if(WIN32)
    set(PLATFORM_RESOURCES resources/app.rc)
elseif(APPLE)
    set(PLATFORM_RESOURCES resources/icons/app.icns)
    # Tell CMake this file is a bundle resource so it lands in
    # Anyfile.app/Contents/Resources/ rather than being compiled.
    set_source_files_properties(resources/icons/app.icns
        PROPERTIES MACOSX_PACKAGE_LOCATION "Resources"
    )
else()
    set(PLATFORM_RESOURCES "")
endif()

qt_add_executable(anyfile_gui
    main_gui.cpp
    ${PLATFORM_RESOURCES}
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

# ── Bundle / executable properties ───────────────────────────────────────────
# MACOSX_BUNDLE        — produce a proper .app bundle on macOS.
# MACOSX_BUNDLE_ICON_FILE — the .icns file placed in Contents/Resources/.
# WIN32_EXECUTABLE     — suppress the Windows console window.
set_target_properties(anyfile_gui PROPERTIES
    MACOSX_BUNDLE                   TRUE
    MACOSX_BUNDLE_BUNDLE_NAME       "Anyfile"
    MACOSX_BUNDLE_BUNDLE_VERSION    "0.1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1"
    MACOSX_BUNDLE_ICON_FILE         "app.icns"
    WIN32_EXECUTABLE                TRUE
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

# ── macOS: deploy Qt frameworks into the .app bundle (requires macdeployqt) ──
# macdeployqt copies all required Qt frameworks, plugins, and QML modules into
# the .app bundle so it is self-contained and can be distributed without
# requiring Qt to be installed on the target machine.
if(APPLE)
    find_program(MACDEPLOYQT_BIN
        NAMES macdeployqt macdeployqt6
        HINTS "${Qt6_DIR}/../../../bin"
        DOC   "Path to the macdeployqt deployment tool"
    )
    if(MACDEPLOYQT_BIN)
        add_custom_command(TARGET anyfile_gui POST_BUILD
            COMMAND "${MACDEPLOYQT_BIN}"
                    "$<TARGET_BUNDLE_DIR:anyfile_gui>"
                    -qmldir=${CMAKE_CURRENT_SOURCE_DIR}/qml
                    -always-overwrite
            COMMENT "Running macdeployqt..."
            VERBATIM
        )
        # macdeployqt copies and patches frameworks, which invalidates the
        # original code signature.  macOS will SIGKILL the app on launch with
        # "Code Signature Invalid" if we don't re-sign.
        #
        # Step 1: strip extended attributes (quarantine xattrs set by macdeployqt
        #         when copying files) — codesign rejects bundles that have them.
        # Step 2: ad-hoc re-sign (--sign -).  No Apple Developer account needed
        #         for local development.
        add_custom_command(TARGET anyfile_gui POST_BUILD
            COMMAND xattr -cr "$<TARGET_BUNDLE_DIR:anyfile_gui>"
            COMMAND codesign --force --deep --sign -
                    "$<TARGET_BUNDLE_DIR:anyfile_gui>"
            COMMENT "Signing .app bundle..."
            VERBATIM
        )
    else()
        message(WARNING
            "macdeployqt not found — the .app bundle will not be self-contained. "
            "Install Qt6 via Homebrew (brew install qt@6) or set Qt6_DIR.")
    endif()
endif()
