import Foundation

final class PigeonError: Error {
  let code: String
  let message: String?
  let details: String?

  init(code: String, message: String?, details: String?) {
    self.code = code
    self.message = message
    self.details = details
  }
}

final class PigeonEventSink<T> {
  func success(_ value: T) {}
}

class StreamEventsStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    sink: PigeonEventSink<NativeGenerateStreamEvent>
  ) {}

  func onCancel(withArguments arguments: Any?) {}
}

struct NativePart {
  let text: String?
  let toolRequestJson: String?
  let toolResponseJson: String?
}

struct NativeMessage {
  let role: String
  let parts: [NativePart]
}

struct NativeGenerateRequest {
  let messages: [NativeMessage]
  let systemInstruction: String?
  let configJson: String?
  let toolsJson: String?
}

struct NativeGenerateResponse {
  let parts: [NativePart]
  let finishReason: String?
  let errorCode: String?
  let errorMessage: String?
}

struct NativeGenerateStreamEvent {
  let requestId: String
  let parts: [NativePart]?
  let done: Bool
  let response: NativeGenerateResponse?
  let errorCode: String?
  let errorMessage: String?
}

protocol FoundationModelsHostApi {
  func isAvailable(completion: @escaping (Result<Bool, Error>) -> Void)

  func generate(
    request: NativeGenerateRequest,
    completion: @escaping (Result<NativeGenerateResponse, Error>) -> Void
  )

  func startGenerateStream(
    request: NativeGenerateRequest,
    completion: @escaping (Result<String, Error>) -> Void
  )

  func cancelGenerateStream(requestId: String) throws
}
