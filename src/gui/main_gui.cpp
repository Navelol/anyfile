#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
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
    app.setWindowIcon(QIcon(":/icons/app.png"));

    // Register bridge as a QML type
    qmlRegisterType<converter::ConverterBridge>("Anyfile", 1, 0, "ConverterBridge");

    QQmlApplicationEngine engine;

    engine.addImportPath("qrc:/");
    // Allow QML modules to be found next to the executable (e.g. deployed bin/qml/)
    engine.addImportPath(QCoreApplication::applicationDirPath() + "/qml");

    const QUrl url(u"qrc:/Anyfile/qml/Main.qml"_s);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [](){ QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
