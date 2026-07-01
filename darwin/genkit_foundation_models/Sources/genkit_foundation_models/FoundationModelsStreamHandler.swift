import Foundation

final class FoundationModelsStreamHandler: StreamEventsStreamHandler {
  private var sink: PigeonEventSink<NativeGenerateStreamEvent>?

  override func onListen(withArguments _: Any?, sink: PigeonEventSink<NativeGenerateStreamEvent>) {
    self.sink = sink
  }

  override func onCancel(withArguments _: Any?) {
    sink = nil
  }

  func send(_ event: NativeGenerateStreamEvent) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.success(event)
    }
  }
}
