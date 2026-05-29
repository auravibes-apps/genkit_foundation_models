#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

public class GenkitFoundationModelsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let api = FoundationModelsHostApiImpl()
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    FoundationModelsHostApiSetup.setUp(binaryMessenger: messenger, api: api)
  }
}
