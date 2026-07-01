import Foundation

@main
struct NativeToolCaptureTest {
  static func main() async throws {
    try testToolDeclarationDecoding()
    try testInvalidToolDeclarationJson()
    try testUsageJsonMapping()
    try await testToolCallRecorderParts()
  }

  private static func testToolDeclarationDecoding() throws {
    let toolsJson = """
      [{"name":"lookup","description":"Lookup data","input":{"type":"object"}}]
      """
    let declarations = try FoundationModelsHostApiImpl.toolDeclarations(
      from: toolsJson
    )

    precondition(declarations.count == 1)
    precondition(declarations[0].name == "lookup")
    precondition(declarations[0].description == "Lookup data")
    precondition(declarations[0].inputSchema?["type"] as? String == "object")
  }

  private static func testInvalidToolDeclarationJson() throws {
    do {
      _ = try FoundationModelsHostApiImpl.toolDeclarations(from: "{}")
      preconditionFailure("Expected invalid tools JSON to throw")
    } catch {
      precondition(true)
    }

    do {
      _ = try FoundationModelsHostApiImpl.toolDeclarations(from: "not json")
      preconditionFailure("Expected malformed tools JSON to throw")
    } catch {
      precondition(true)
    }
  }

  private static func testUsageJsonMapping() throws {
    guard let json = FoundationModelsHostApiImpl.usageJson(from: [
      "inputTokens": 3,
      "outputTokens": 5,
      "totalTokens": 8,
      "thoughtsTokens": 2,
      "cachedContentTokens": 1,
      "ignored": 99,
      "custom": ["provider": "foundation_models"],
    ]),
      let data = json.data(using: .utf8),
      let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      preconditionFailure("Expected usage JSON")
    }

    precondition(decoded["inputTokens"] as? Int == 3)
    precondition(decoded["outputTokens"] as? Int == 5)
    precondition(decoded["totalTokens"] as? Int == 8)
    precondition(decoded["thoughtsTokens"] as? Int == 2)
    precondition(decoded["cachedContentTokens"] as? Int == 1)
    precondition(decoded["ignored"] == nil)
    let custom = decoded["custom"] as? [String: String]
    precondition(custom?["provider"] == "foundation_models")

    let reflectedJson = FoundationModelsHostApiImpl.usageJson(
      fromUsageValue: FakeUsage(
        input: FakeUsageBucket(
          totalTokenCount: 7,
          cachedTokenCount: 2,
          reasoningTokenCount: nil
        ),
        output: FakeUsageBucket(
          totalTokenCount: 11,
          cachedTokenCount: nil,
          reasoningTokenCount: 3
        )
      )
    )
    guard let reflectedJson,
          let reflectedData = reflectedJson.data(using: .utf8),
          let reflected = try JSONSerialization.jsonObject(with: reflectedData)
            as? [String: Any]
    else {
      preconditionFailure("Expected reflected usage JSON")
    }

    precondition(reflected["inputTokens"] as? Int == 7)
    precondition(reflected["outputTokens"] as? Int == 11)
    precondition(reflected["totalTokens"] as? Int == 18)
    precondition(reflected["thoughtsTokens"] as? Int == 3)
    precondition(reflected["cachedContentTokens"] as? Int == 2)
  }

  private static func testToolCallRecorderParts() async throws {
    let recorder = NativeToolCallRecorder(refPrefix: "request")
    await recorder.record(name: "lookup", arguments: "{\"q\":\"aura\"}")
    await recorder.record(name: "time", arguments: "{}")
    await recorder.record(name: "echo", arguments: "[\"a\"]")

    let parts = await recorder.parts()
    precondition(parts.count == 3)
    try assertToolRequest(
      parts[0].toolRequestJson,
      ref: "request_call_0",
      name: "lookup",
      input: ["q": "aura"]
    )
    try assertToolRequest(
      parts[1].toolRequestJson,
      ref: "request_call_1",
      name: "time",
      input: [:]
    )
    try assertToolRequestArrayInput(
      parts[2].toolRequestJson,
      ref: "request_call_2",
      name: "echo",
      input: ["a"]
    )
  }

  private static func assertToolRequest(
    _ json: String?,
    ref: String,
    name: String,
    input: [String: String]
  ) throws {
    guard let json, let data = json.data(using: .utf8),
          let decoded = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
    else {
      preconditionFailure("Invalid tool request JSON")
    }

    precondition(decoded["ref"] as? String == ref)
    precondition(decoded["name"] as? String == name)
    let decodedInput = decoded["input"] as? [String: String] ?? [:]
    precondition(decodedInput == input)
  }

  private static func assertToolRequestArrayInput(
    _ json: String?,
    ref: String,
    name: String,
    input: [String]
  ) throws {
    guard let json, let data = json.data(using: .utf8),
          let decoded = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
    else {
      preconditionFailure("Invalid tool request JSON")
    }

    precondition(decoded["ref"] as? String == ref)
    precondition(decoded["name"] as? String == name)
    let decodedInput = decoded["input"] as? [String] ?? []
    precondition(decodedInput == input)
  }
}

private struct FakeUsage {
  let input: FakeUsageBucket
  let output: FakeUsageBucket
}

private struct FakeUsageBucket {
  let totalTokenCount: Int
  let cachedTokenCount: Int?
  let reasoningTokenCount: Int?
}
