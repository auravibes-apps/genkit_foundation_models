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
  func success(_ _: T) {
    // Typecheck-only stub. Runtime event delivery is tested through generated code.
  }
}

class StreamEventsStreamHandler {
  func onListen(
    withArguments _: Any?,
    sink _: PigeonEventSink<NativeGenerateStreamEvent>
  ) {
    // Typecheck-only stub. Production stream handlers override this method.
  }

  func onCancel(withArguments _: Any?) {
    // Typecheck-only stub. Production stream handlers override this method.
  }
}

struct NativePart {
  let text: String?
  let toolRequestJson: String?
  let toolResponseJson: String?
  let reasoningText: String?
  let metadataJson: String?
  let customJson: String?

  init(
    text: String? = nil,
    toolRequestJson: String? = nil,
    toolResponseJson: String? = nil,
    reasoningText: String? = nil,
    metadataJson: String? = nil,
    customJson: String? = nil
  ) {
    self.text = text
    self.toolRequestJson = toolRequestJson
    self.toolResponseJson = toolResponseJson
    self.reasoningText = reasoningText
    self.metadataJson = metadataJson
    self.customJson = customJson
  }
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
  let usageJson: String?
  let customJson: String?
  let rawJson: String?

  init(
    parts: [NativePart],
    finishReason: String? = nil,
    errorCode: String? = nil,
    errorMessage: String? = nil,
    usageJson: String? = nil,
    customJson: String? = nil,
    rawJson: String? = nil
  ) {
    self.parts = parts
    self.finishReason = finishReason
    self.errorCode = errorCode
    self.errorMessage = errorMessage
    self.usageJson = usageJson
    self.customJson = customJson
    self.rawJson = rawJson
  }
}

struct NativeGenerateStreamEvent {
  let requestId: String
  let parts: [NativePart]?
  let done: Bool
  let response: NativeGenerateResponse?
  let errorCode: String?
  let errorMessage: String?
  let customJson: String?

  init(
    requestId: String,
    parts: [NativePart]? = nil,
    done: Bool,
    response: NativeGenerateResponse? = nil,
    errorCode: String? = nil,
    errorMessage: String? = nil,
    customJson: String? = nil
  ) {
    self.requestId = requestId
    self.parts = parts
    self.done = done
    self.response = response
    self.errorCode = errorCode
    self.errorMessage = errorMessage
    self.customJson = customJson
  }
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
