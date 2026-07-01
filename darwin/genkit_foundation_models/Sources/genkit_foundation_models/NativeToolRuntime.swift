import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

struct NativeToolDeclaration {
  let name: String
  let description: String
  let inputSchema: [String: Any]?
}

actor NativeToolCallRecorder {
  init(refPrefix: String = UUID().uuidString) {
    self.refPrefix = refPrefix
  }

  private let refPrefix: String
  private var calls: [(name: String, arguments: String)] = []

  func record(name: String, arguments: String) {
    calls.append((name: name, arguments: arguments))
  }

  func parts() -> [NativePart] {
    calls.enumerated().map { index, call in
      NativePart(
        text: nil,
        toolRequestJson: Self.toolRequestJson(
          ref: "\(refPrefix)_call_\(index)",
          name: call.name,
          arguments: call.arguments
        ),
        toolResponseJson: nil
      )
    }
  }

  private static func toolRequestJson(
    ref: String,
    name: String,
    arguments: String
  ) -> String {
    let decodedArguments = decodeJsonValue(arguments) ?? [:]
    let payload: [String: Any] = [
      "ref": ref,
      "name": name,
      "input": decodedArguments
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8)
    else {
      return "{\"ref\":\"\(ref)\",\"name\":\"\(name)\",\"input\":{}}"
    }
    return json
  }

  private static func decodeJsonValue(_ json: String) -> Any? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }
}

#if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  struct NativeToolRuntime {
    let tools: [any Tool]
    private let recorder: NativeToolCallRecorder

    init(declarations: [NativeToolDeclaration]) throws {
      let recorder = NativeToolCallRecorder()
      self.recorder = recorder
      tools = declarations.map { declaration in
        NativeCaptureTool(
          declaration: declaration,
          recorder: recorder
        )
      }
    }

    func capturedParts() async -> [NativePart] {
      await recorder.parts()
    }
  }

  @available(iOS 26.0, macOS 26.0, *)
  struct NativeCaptureTool: Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema
    private let recorder: NativeToolCallRecorder

    init(declaration: NativeToolDeclaration, recorder: NativeToolCallRecorder) {
      name = declaration.name
      description = declaration.description
      parameters = Self.parameters(from: declaration.inputSchema)
      self.recorder = recorder
    }

    func call(arguments: GeneratedContent) async throws -> Prompt {
      await recorder.record(name: name, arguments: arguments.jsonString)
      throw NativeToolCaptureSignal()
    }

    private static func parameters(from schema: [String: Any]?) -> GenerationSchema {
      guard let schema,
            let dynamicSchema = NativeJSONSchemaConverter(schema: schema).makeSchema(),
            let generationSchema = try? GenerationSchema(
              root: dynamicSchema,
              dependencies: []
            )
      else {
        return GenerationSchema(type: String.self, description: "Tool input", properties: [])
      }
      return generationSchema
    }
  }

  struct NativeToolCaptureSignal: Error {}

  @available(iOS 26.0, macOS 26.0, *)
  extension LanguageModelSession.ToolCallError {
    var isNativeToolCapture: Bool {
      underlyingError is NativeToolCaptureSignal
    }
  }
#endif
