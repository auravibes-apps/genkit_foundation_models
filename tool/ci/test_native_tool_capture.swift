import Foundation

@main
struct NativeToolCaptureTest {
  static func main() async throws {
    try testToolDeclarationDecoding()
    try testInvalidToolDeclarationJson()
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
