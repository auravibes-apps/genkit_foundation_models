import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

extension FoundationModelsHostApiImpl {
  static func usageJson(from values: [String: Any]) -> String? {
    var usage: [String: Any] = [:]
    for key in [
      "inputTokens",
      "outputTokens",
      "totalTokens",
      "thoughtsTokens",
      "cachedContentTokens",
      "inputCharacters",
    ] {
      if let value = values[key] {
        usage[key] = value
      }
    }
    if let custom = values["custom"] {
      usage["custom"] = custom
    }
    guard !usage.isEmpty,
          JSONSerialization.isValidJSONObject(usage),
          let data = try? JSONSerialization.data(withJSONObject: usage),
          let json = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return json
  }

  static func usageJson(fromUsageValue usage: Any) -> String? {
    var values: [String: Any] = [:]
    if let input = mirrorChild(named: "input", in: usage) {
      values["inputTokens"] = intChild(named: "totalTokenCount", in: input)
      values["cachedContentTokens"] = intChild(
        named: "cachedTokenCount",
        in: input
      )
    }
    if let output = mirrorChild(named: "output", in: usage) {
      values["outputTokens"] = intChild(named: "totalTokenCount", in: output)
      values["thoughtsTokens"] = intChild(
        named: "reasoningTokenCount",
        in: output
      )
    }
    if let inputTokens = values["inputTokens"] as? Int,
       let outputTokens = values["outputTokens"] as? Int {
      values["totalTokens"] = inputTokens + outputTokens
    }
    return usageJson(from: values)
  }

  private static func mirrorChild(named name: String, in value: Any) -> Any? {
    Mirror(reflecting: value).children.first { $0.label == name }?.value
  }

  private static func intChild(named name: String, in value: Any) -> Int? {
    guard let child = mirrorChild(named: name, in: value) else { return nil }
    guard let unwrapped = unwrapOptional(child) else { return nil }
    if let int = unwrapped as? Int { return int }
    if let int64 = unwrapped as? Int64 { return Int(int64) }
    if let uint = unwrapped as? UInt { return Int(uint) }
    if let uint64 = unwrapped as? UInt64 { return Int(uint64) }
    return nil
  }

  private static func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
  }
}

#if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  extension FoundationModelsHostApiImpl {
    static func usageJson(
      from response: LanguageModelSession.Response<String>
    ) -> String? {
      #if FOUNDATION_MODELS_HAS_USAGE
        return usageJson(fromUsageValue: response.usage)
      #else
        guard let usage = mirrorChild(named: "usage", in: response) else {
          return nil
        }
        return usageJson(fromUsageValue: usage)
      #endif
    }
  }
#endif
