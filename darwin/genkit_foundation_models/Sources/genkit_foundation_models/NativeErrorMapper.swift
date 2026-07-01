import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

extension FoundationModelsHostApiImpl {
  static func unavailableError(_ message: String) -> PigeonError {
    PigeonError(
      code: "foundation_models_unavailable",
      message: message,
      details: nil
    )
  }

  #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    static func availabilityError(for availability: SystemLanguageModel.Availability) -> PigeonError {
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
    static func generationError(_ error: Error) -> PigeonError {
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
        case .rateLimited:
          return PigeonError(
            code: "rate_limited",
            message: generationError.localizedDescription,
            details: nil
          )
        case .concurrentRequests:
          return PigeonError(
            code: "concurrent_requests",
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
}
