#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

public class GenkitFoundationModelsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let streamHandler = FoundationModelsStreamHandler()
    let api = FoundationModelsHostApiImpl(streamHandler: streamHandler)
    FoundationModelsHostApiSetup.setUp(binaryMessenger: messenger, api: api)
    StreamEventsStreamHandler.register(with: messenger, streamHandler: streamHandler)
  }
}
