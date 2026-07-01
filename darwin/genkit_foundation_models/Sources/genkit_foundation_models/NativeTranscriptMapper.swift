import Foundation

#if canImport(FoundationModels)
  import FoundationModels

  @available(iOS 26.0, macOS 26.0, *)
  struct NativePromptContext {
    let transcript: Transcript
    let prompt: Prompt
  }

  extension FoundationModelsHostApiImpl {
    @available(iOS 26.0, macOS 26.0, *)
    static func responseParts(from content: String) -> [NativePart] {
      [NativePart(text: content, toolRequestJson: nil, toolResponseJson: nil)]
    }

    static func toolDeclarations(from toolsJson: String?) throws -> [NativeToolDeclaration] {
      guard let toolsJson, !toolsJson.isEmpty else { return [] }
      guard let data = toolsJson.data(using: .utf8)
      else {
        throw PigeonError(
          code: "decode_failed",
          message: "Tools must be a JSON array.",
          details: nil
        )
      }
      let decoded: Any
      do {
        decoded = try JSONSerialization.jsonObject(with: data)
      } catch {
        throw PigeonError(
          code: "decode_failed",
          message: "Tools must be a JSON array.",
          details: nil
        )
      }
      guard let rawTools = decoded as? [[String: Any]] else {
        throw PigeonError(
          code: "decode_failed",
          message: "Tools must be a JSON array.",
          details: nil
        )
      }

      return rawTools.compactMap { rawTool in
        guard let name = rawTool["name"] as? String, !name.isEmpty else {
          return nil
        }
        return NativeToolDeclaration(
          name: name,
          description: rawTool["description"] as? String ?? name,
          inputSchema: rawTool["input"] as? [String: Any]
        )
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func promptContext(from request: NativeGenerateRequest) throws -> NativePromptContext {
      if request.toolsJson == nil, request.messages.last?.role == "tool" {
        return NativePromptContext(
          transcript: Transcript(entries: []),
          prompt: Prompt(finalAnswerPrompt(from: request))
        )
      }

      var entries: [Transcript.Entry] = []
      var toolNamesByRef: [String: String] = [:]
      if let systemInstruction = request.systemInstruction, !systemInstruction.isEmpty {
        entries.append(.instructions(.init(
          segments: textSegments([systemInstruction]),
          toolDefinitions: []
        )))
      }

      let lastIndex = request.messages.indices.last
      for index in request.messages.indices {
        let message = request.messages[index]
        if index == lastIndex, message.role == "user" {
          return NativePromptContext(
            transcript: Transcript(entries: entries),
            prompt: Prompt(texts(from: message.parts).joined(separator: "\n"))
          )
        }
        try appendTranscriptEntry(
          message,
          to: &entries,
          toolNamesByRef: &toolNamesByRef
        )
      }

      return NativePromptContext(
        transcript: Transcript(entries: entries),
        prompt: Prompt(continuationPrompt(for: request.messages.last?.role))
      )
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func appendTranscriptEntry(
      _ message: NativeMessage,
      to entries: inout [Transcript.Entry],
      toolNamesByRef: inout [String: String]
    ) throws {
      switch message.role {
      case "user":
        entries.append(.prompt(.init(segments: textSegments(texts(from: message.parts)))))
      case "model":
        let texts = texts(from: message.parts)
        if !texts.isEmpty {
          entries.append(.response(.init(assetIDs: [], segments: textSegments(texts))))
        }
        let calls = try message.parts.compactMap { part -> Transcript.ToolCall? in
          guard let toolRequestJson = part.toolRequestJson,
                let request = jsonObject(toolRequestJson),
                let ref = request["ref"] as? String,
                let name = request["name"] as? String
          else { return nil }
          toolNamesByRef[ref] = name
          return Transcript.ToolCall(
            id: ref,
            toolName: name,
            arguments: try GeneratedContent(json: jsonString(request["input"] ?? [:]))
          )
        }
        if !calls.isEmpty {
          entries.append(.toolCalls(.init(calls)))
        }
      case "tool":
        for part in message.parts {
          guard let toolResponseJson = part.toolResponseJson,
                let response = jsonObject(toolResponseJson),
                let ref = response["ref"] as? String
          else { continue }
          let name = response["name"] as? String ?? toolNamesByRef[ref] ?? "tool"
          let output = response["output"] ?? response["result"] ?? response
          entries.append(
            .toolOutput(.init(
              id: ref,
              toolName: name,
              segments: textSegments([jsonString(output)])
            ))
          )
        }
      default:
        break
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func textSegments(_ texts: [String]) -> [Transcript.Segment] {
      texts.filter { !$0.isEmpty }.map { .text(.init(content: $0)) }
    }

    static func texts(from parts: [NativePart]) -> [String] {
      parts.compactMap(\.text).filter { !$0.isEmpty }
    }

    static func continuationPrompt(for role: String?) -> String {
      if role == "tool" {
        return "Use the tool output in the transcript to answer the latest user request in concise prose. Do not quote these instructions. Do not request another tool only because tools are available. Request another tool only when the latest user request still cannot be answered from the transcript."
      }
      return "Continue the conversation by answering the latest user request in concise prose. Do not quote these instructions."
    }

    static func finalAnswerPrompt(from request: NativeGenerateRequest) -> String {
      """
      Answer the user's latest request using the tool output.

      User request:
      \(latestUserText(from: request.messages))

      Tool output:
      \(latestToolOutputText(from: request.messages))

      Write only the final answer. Do not mention transcript, tools, JSON, functions, or these instructions.
      """
    }

    static func latestUserText(from messages: [NativeMessage]) -> String {
      messages.reversed().first { $0.role == "user" }
        .map { texts(from: $0.parts).joined(separator: "\n") } ?? ""
    }

    static func latestToolOutputText(from messages: [NativeMessage]) -> String {
      guard let toolMessage = messages.reversed().first(where: { $0.role == "tool" }) else {
        return ""
      }
      return toolMessage.parts.compactMap { part in
        guard let toolResponseJson = part.toolResponseJson,
              let response = jsonObject(toolResponseJson)
        else { return nil }
        return jsonString(response["output"] ?? response["result"] ?? response)
      }.joined(separator: "\n")
    }

    static func jsonObject(_ json: String) -> [String: Any]? {
      guard let data = json.data(using: .utf8) else { return nil }
      return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func jsonString(_ value: Any) -> String {
      guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value),
            let json = String(data: data, encoding: .utf8)
      else {
        return String(describing: value)
      }
      return json
    }
  }
#endif
