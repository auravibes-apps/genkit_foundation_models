import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

final class FoundationModelsStreamHandler: StreamEventsStreamHandler {
  private var sink: PigeonEventSink<NativeGenerateStreamEvent>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<NativeGenerateStreamEvent>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func send(_ event: NativeGenerateStreamEvent) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.success(event)
    }
  }
}

final class FoundationModelsHostApiImpl: FoundationModelsHostApi {
  init(streamHandler: FoundationModelsStreamHandler? = nil) {
    self.streamHandler = streamHandler
  }

  private let streamHandler: FoundationModelsStreamHandler?
  private var streamTasks: [String: Task<Void, Never>] = [:]

  func isAvailable(completion: @escaping (Result<Bool, Error>) -> Void) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        completion(.success(SystemLanguageModel.default.isAvailable))
      } else {
        completion(.success(false))
      }
    #else
      completion(.success(false))
    #endif
  }

  func generate(
    request: NativeGenerateRequest,
    completion: @escaping (Result<NativeGenerateResponse, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *) else {
        completion(.failure(Self.unavailableError("FoundationModels requires iOS 26.0 or macOS 26.0.")))
        return
      }

      let model = SystemLanguageModel.default
      guard model.isAvailable else {
        completion(.failure(Self.availabilityError(for: model.availability)))
        return
      }

      let prompt = Self.prompt(from: request)
      let options: GenerationOptions
      do {
        options = try Self.generationOptions(from: request.configJson)
      } catch {
        completion(.failure(error))
        return
      }

      Task {
        do {
          let session = LanguageModelSession(
            model: model,
            instructions: request.systemInstruction
          )
          let response = try await session.respond(to: prompt, options: options)
          completion(.success(NativeGenerateResponse(
            parts: Self.responseParts(from: response.content, toolsJson: request.toolsJson),
            finishReason: "stop",
            errorCode: nil,
            errorMessage: nil
          )))
        } catch {
          completion(.failure(Self.generationError(error)))
        }
      }
    #else
      completion(.failure(PigeonError(
        code: "foundation_models_unavailable",
        message: "FoundationModels framework is unavailable for this SDK or platform.",
        details: nil
      )))
    #endif
  }

  func startGenerateStream(
    request: NativeGenerateRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *) else {
        completion(.failure(Self.unavailableError("FoundationModels requires iOS 26.0 or macOS 26.0.")))
        return
      }

      let model = SystemLanguageModel.default
      guard model.isAvailable else {
        completion(.failure(Self.availabilityError(for: model.availability)))
        return
      }

      let prompt = Self.prompt(from: request)
      let options: GenerationOptions
      do {
        options = try Self.generationOptions(from: request.configJson)
      } catch {
        completion(.failure(error))
        return
      }

      let requestId = UUID().uuidString
      streamTasks[requestId] = Task { [weak self, streamHandler] in
        defer { self?.streamTasks.removeValue(forKey: requestId) }
        do {
          let session = LanguageModelSession(
            model: model,
            instructions: request.systemInstruction
          )
          let stream = session.streamResponse(to: prompt, options: options)
          let shouldStreamText = request.toolsJson == nil
          for try await snapshot in stream {
            if !shouldStreamText { continue }
            streamHandler?.send(NativeGenerateStreamEvent(
              requestId: requestId,
              parts: [NativePart(text: snapshot.content, toolRequestJson: nil, toolResponseJson: nil)],
              done: false,
              response: nil,
              errorCode: nil,
              errorMessage: nil
            ))
          }

          let response = try await stream.collect()
          streamHandler?.send(NativeGenerateStreamEvent(
            requestId: requestId,
            parts: nil,
            done: true,
            response: NativeGenerateResponse(
              parts: Self.responseParts(from: response.content, toolsJson: request.toolsJson),
              finishReason: "stop",
              errorCode: nil,
              errorMessage: nil
            ),
            errorCode: nil,
            errorMessage: nil
          ))
        } catch {
          let pigeonError = Self.generationError(error)
          streamHandler?.send(NativeGenerateStreamEvent(
            requestId: requestId,
            parts: nil,
            done: true,
            response: nil,
            errorCode: pigeonError.code,
            errorMessage: pigeonError.message
          ))
        }
      }
      completion(.success(requestId))
    #else
      completion(.failure(PigeonError(
        code: "foundation_models_unavailable",
        message: "FoundationModels framework is unavailable for this SDK or platform.",
        details: nil
      )))
    #endif
  }

  func cancelGenerateStream(requestId: String) throws {
    streamTasks.removeValue(forKey: requestId)?.cancel()
  }

  private static func prompt(from request: NativeGenerateRequest) -> String {
    let conversation = request.messages
      .map { message in
        let text = message.parts.map { part in
          if let text = part.text { return text }
          if let toolRequest = part.toolRequestJson { return "Tool request: \(toolRequest)" }
          if let toolResponse = part.toolResponseJson { return "Tool response: \(toolResponse)" }
          return ""
        }.joined(separator: "\n")
        return "\(message.role): \(text)"
      }
      .joined(separator: "\n")

    guard let toolsJson = request.toolsJson, !toolsJson.isEmpty else {
      return conversation
    }

    if hasToolResponse(request) {
      return """
        Tool results are already provided in the conversation.
        Answer normally in prose using those tool results.
        Do not request tools again.
        Do not output tool_call tags or JSON tool requests.

        Conversation:
        \(conversation)
        """
    }

    return """
      You can ask the host app to run tools, but you cannot run tools yourself.
      If a tool is needed, respond with only this exact tag shape and no prose:
      <tool_call>{"name":"tool_name","arguments":{}}</tool_call>
      Use only tool names from Available tools JSON. Never invent tool names.
      Writing text is not a tool. If you need to write, answer normally in prose.
      If no tool is needed, answer normally.

      Available tools JSON:
      \(toolsJson)

      Conversation:
      \(conversation)
      """
  }

  private static func responseParts(from content: String, toolsJson: String?) -> [NativePart] {
    [NativePart(text: content, toolRequestJson: nil, toolResponseJson: nil)]
  }

  private static func hasToolResponse(_ request: NativeGenerateRequest) -> Bool {
    request.messages.contains { message in
      message.parts.contains { part in
        part.toolResponseJson != nil
      }
    }
  }

  #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func generationOptions(from configJson: String?) throws -> GenerationOptions {
      guard let configJson else {
        return GenerationOptions()
      }

      guard let data = configJson.data(using: .utf8),
            let config = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        throw PigeonError(
          code: "decode_failed",
          message: "Generation config must be a JSON object.",
          details: nil
        )
      }

      var sampling: GenerationOptions.SamplingMode?
      if let topK = config["topK"] as? Int {
        sampling = .random(top: topK)
      } else if let topP = config["topP"] as? Double {
        sampling = .random(probabilityThreshold: topP)
      }

      return GenerationOptions(
        sampling: sampling,
        temperature: config["temperature"] as? Double,
        maximumResponseTokens: config["maxOutputTokens"] as? Int
      )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func availabilityError(for availability: SystemLanguageModel.Availability) -> PigeonError {
      switch availability {
      case .available:
        return unavailableError("FoundationModels is available.")
      case .unavailable(.appleIntelligenceNotEnabled):
        return PigeonError(
          code: "apple_intelligence_disabled",
          message: "Apple Intelligence is not enabled.",
          details: nil
        )
      case .unavailable(.deviceNotEligible):
        return PigeonError(
          code: "device_not_eligible",
          message: "This device is not eligible for FoundationModels.",
          details: nil
        )
      case .unavailable(.modelNotReady):
        return PigeonError(
          code: "model_not_ready",
          message: "FoundationModels assets are not ready.",
          details: nil
        )
      @unknown default:
        return unavailableError("FoundationModels is unavailable.")
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func generationError(_ error: Error) -> PigeonError {
      if let generationError = error as? LanguageModelSession.GenerationError {
        switch generationError {
        case .assetsUnavailable:
          return unavailableError(generationError.localizedDescription)
        case .guardrailViolation, .refusal:
          return PigeonError(
            code: "generation_blocked",
            message: generationError.localizedDescription,
            details: nil
          )
        case .decodingFailure:
          return PigeonError(
            code: "decode_failed",
            message: generationError.localizedDescription,
            details: nil
          )
        default:
          return PigeonError(
            code: "generation_failed",
            message: generationError.localizedDescription,
            details: nil
          )
        }
      }

      return PigeonError(
        code: "generation_failed",
        message: error.localizedDescription,
        details: nil
      )
    }

  #endif

  private static func unavailableError(_ message: String) -> PigeonError {
    PigeonError(
      code: "foundation_models_unavailable",
      message: message,
      details: nil
    )
  }
}
