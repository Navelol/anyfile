#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QTimer>
#include <QtQml>
#include <QQuickStyle>

#include "ConverterBridge.h"
#include "../core/ToolPaths.h"

int main(int argc, char* argv[]) {
    using namespace Qt::StringLiterals;
    converter::ToolPaths::init();
    QQuickStyle::setStyle("Basic");
    QApplication app(argc, argv);
    app.setApplicationName("Anyfile");
    app.setApplicationVersion("0.1");
    app.setOrganizationName("Anyfile");
    // Window-frame icon (all platforms). On macOS the dock icon comes from
    // the .icns bundle resource set via MACOSX_BUNDLE_ICON_FILE in CMake.
    app.setWindowIcon(QIcon(":/icons/app.png"));

    // Register bridge as a QML type
    qmlRegisterType<converter::ConverterBridge>("Anyfile", 1, 0, "ConverterBridge");

    QQmlApplicationEngine engine;

    engine.addImportPath("qrc:/qt/qml");
    // Allow QML modules to be found next to the executable (e.g. deployed bin/qml/)
    engine.addImportPath(QCoreApplication::applicationDirPath() + "/qml");

    const QUrl url(u"qrc:/qt/qml/Anyfile/qml/Main.qml"_s);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [](){ QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    // --smoke-test: verify QML loads successfully, then exit.
    // Used by CI to confirm the GUI launches without crashing.
    if (app.arguments().contains("--smoke-test")) {
        QTimer::singleShot(2000, &app, []{ QCoreApplication::exit(0); });
    }

    return app.exec();
}
