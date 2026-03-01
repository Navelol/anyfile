#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QtQml>

#include "ConverterBridge.h"

int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("Anyfile");
    app.setApplicationVersion("0.1");
    app.setOrganizationName("Anyfile");
    app.setWindowIcon(QIcon(":/icons/app.png"));

    // Register bridge as a QML type
    qmlRegisterType<converter::ConverterBridge>("Anyfile", 1, 0, "ConverterBridge");

    QQmlApplicationEngine engine;

    engine.addImportPath("qrc:/");

    const QUrl url(u"qrc:/Anyfile/qml/Main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [](){ QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
