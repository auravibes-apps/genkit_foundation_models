import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

final class FoundationModelsHostApiImpl: FoundationModelsHostApi {
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
            parts: [NativePart(text: response.content, toolRequestJson: nil, toolResponseJson: nil)],
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

  private static func prompt(from request: NativeGenerateRequest) -> String {
    request.messages
      .map { message in
        let text = message.parts.compactMap(\.text).joined(separator: "\n")
        return "\(message.role): \(text)"
      }
      .joined(separator: "\n")
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
