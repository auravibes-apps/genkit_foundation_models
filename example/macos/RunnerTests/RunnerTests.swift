import Cocoa
import FlutterMacOS
@testable import genkit_foundation_models
import XCTest

class RunnerTests: XCTestCase {

  func testHostApiSetupRegistersExpectedChannels() {
    let messenger = MockBinaryMessenger()

    FoundationModelsHostApiSetup.setUp(
      binaryMessenger: messenger,
      api: MockFoundationModelsHostApi())

    XCTAssertNotNil(
      messenger.handlers[
        "dev.flutter.pigeon.genkit_foundation_models.FoundationModelsHostApi.generate"])
    XCTAssertNotNil(
      messenger.handlers[
        "dev.flutter.pigeon.genkit_foundation_models.FoundationModelsHostApi.startGenerateStream"])
    XCTAssertNotNil(
      messenger.handlers[
        "dev.flutter.pigeon.genkit_foundation_models.FoundationModelsHostApi.cancelGenerateStream"])
    XCTAssertNotNil(
      messenger.handlers[
        "dev.flutter.pigeon.genkit_foundation_models.FoundationModelsHostApi.isAvailable"])
  }

  func testNativeResponseCodecRoundTrip() {
    let response = NativeGenerateResponse(
      parts: [
        NativePart(
          text: "hello",
          reasoningText: "debug",
          metadataJson: #"{"source":"test"}"#,
          customJson: #"{"visible":false}"#)
      ],
      finishReason: "stop",
      customJson: #"{"response":true}"#,
      rawJson: #"{"native":"value"}"#)

    let codec = FoundationModelsApiPigeonCodec.shared
    let decoded = codec.decode(codec.encode(response)) as? NativeGenerateResponse

    XCTAssertEqual(decoded, response)
  }

  func testStreamHandlerSendsEventsUntilCancel() {
    let handler = FoundationModelsStreamHandler()
    var events = [NativeGenerateStreamEvent]()
    let sink = PigeonEventSink<NativeGenerateStreamEvent> { value in
      if let event = value as? NativeGenerateStreamEvent {
        events.append(event)
      }
    }

    handler.onListen(withArguments: nil, sink: sink)
    handler.send(NativeGenerateStreamEvent(requestId: "one", done: false))
    waitForMainQueue()

    handler.onCancel(withArguments: nil)
    handler.send(NativeGenerateStreamEvent(requestId: "two", done: false))
    waitForMainQueue()

    XCTAssertEqual(events.map(\.requestId), ["one"])
  }

  private func waitForMainQueue() {
    let expectation = expectation(description: "main queue")
    DispatchQueue.main.async { expectation.fulfill() }
    wait(for: [expectation], timeout: 1)
  }

}

private final class MockFoundationModelsHostApi: FoundationModelsHostApi {
  func generate(
    request _: NativeGenerateRequest,
    completion: @escaping (Result<NativeGenerateResponse, Error>) -> Void
  ) {
    completion(.success(NativeGenerateResponse(parts: [])))
  }

  func startGenerateStream(
    request _: NativeGenerateRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    completion(.success("request"))
  }

  func cancelGenerateStream(requestId _: String) throws {
    // No-op: registration tests only need the generated host API handler.
  }

  func isAvailable(completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(.success(false))
  }
}

private final class MockBinaryMessenger: NSObject, FlutterBinaryMessenger {
  private(set) var handlers = [String: FlutterBinaryMessageHandler]()

  func send(onChannel _: String, message _: Data?) {
    // No-op: tests verify handler registration, not outbound messages.
  }

  func send(
    onChannel _: String,
    message _: Data?,
    binaryReply _: FlutterBinaryReply? = nil
  ) {
    // No-op: tests verify handler registration, not outbound replies.
  }

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
  ) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return FlutterBinaryMessengerConnection(handlers.count)
  }

  func cleanUpConnection(_: FlutterBinaryMessengerConnection) {
    // No-op: tests do not exercise connection cleanup.
  }
}
