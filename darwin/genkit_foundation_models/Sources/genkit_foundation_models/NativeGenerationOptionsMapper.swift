import Foundation

#if canImport(FoundationModels)
  import FoundationModels

  extension FoundationModelsHostApiImpl {
    @available(iOS 26.0, macOS 26.0, *)
    static func generationOptions(from configJson: String?) throws -> GenerationOptions {
      guard let configJson else {
        return GenerationOptions()
      }

      guard let data = configJson.data(using: .utf8)
      else {
        throw PigeonError(
          code: "decode_failed",
          message: "Generation config must be a JSON object.",
          details: nil
        )
      }
      let decoded: Any
      do {
        decoded = try JSONSerialization.jsonObject(with: data)
      } catch {
        throw PigeonError(
          code: "decode_failed",
          message: "Generation config must be a JSON object.",
          details: nil
        )
      }
      guard let config = decoded as? [String: Any] else {
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
  }
#endif
