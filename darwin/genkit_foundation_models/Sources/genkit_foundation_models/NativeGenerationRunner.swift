import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

final class NativeGenerationRunner {
  init(streamHandler: FoundationModelsStreamHandler? = nil) {
    self.streamHandler = streamHandler
  }

  private let streamHandler: FoundationModelsStreamHandler?
  private var streamTasks: [String: Task<Void, Never>] = [:]

  #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private struct NativeGenerationSetup {
      let model: SystemLanguageModel
      let toolDeclarations: [NativeToolDeclaration]
      let promptContext: NativePromptContext
      let options: GenerationOptions
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func makeSetup(
      request: NativeGenerateRequest
    ) throws -> NativeGenerationSetup {
      let model = SystemLanguageModel.default
      guard model.isAvailable else {
        throw FoundationModelsHostApiImpl.availabilityError(for: model.availability)
      }

      return NativeGenerationSetup(
        model: model,
        toolDeclarations: try FoundationModelsHostApiImpl.toolDeclarations(
          from: request.toolsJson
        ),
        promptContext: try FoundationModelsHostApiImpl.promptContext(from: request),
        options: try FoundationModelsHostApiImpl.generationOptions(
          from: request.configJson
        )
      )
    }
  #endif

  func generate(
    request: NativeGenerateRequest,
    completion: @escaping (Result<NativeGenerateResponse, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *) else {
        completion(.failure(FoundationModelsHostApiImpl.unavailableError("FoundationModels requires iOS 26.0 or macOS 26.0.")))
        return
      }

      let setup: NativeGenerationSetup
      do {
        setup = try makeSetup(request: request)
      } catch {
        completion(.failure(error))
        return
      }

      Task {
        var toolRuntime: NativeToolRuntime?
        do {
          let runtime = try NativeToolRuntime(declarations: setup.toolDeclarations)
          toolRuntime = runtime
          let session = LanguageModelSession(
            model: setup.model,
            tools: runtime.tools,
            transcript: setup.promptContext.transcript
          )
          let response: LanguageModelSession.Response<String>
          do {
            response = try await session.respond(
              to: setup.promptContext.prompt,
              options: setup.options
            )
          } catch let error as LanguageModelSession.ToolCallError
              where error.isNativeToolCapture {
            completion(.success(NativeGenerateResponse(
              parts: await runtime.capturedParts(),
              finishReason: "tool_calls",
              errorCode: nil,
              errorMessage: nil
            )))
            return
          }
          completion(.success(NativeGenerateResponse(
            parts: FoundationModelsHostApiImpl.responseParts(from: response.content),
            finishReason: "stop",
            errorCode: nil,
            errorMessage: nil
          )))
        } catch {
          let capturedParts = await toolRuntime?.capturedParts() ?? []
          if !capturedParts.isEmpty {
            completion(.success(NativeGenerateResponse(
              parts: capturedParts,
              finishReason: "tool_calls",
              errorCode: nil,
              errorMessage: nil
            )))
            return
          }
          completion(.failure(FoundationModelsHostApiImpl.generationError(error)))
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
        completion(.failure(FoundationModelsHostApiImpl.unavailableError("FoundationModels requires iOS 26.0 or macOS 26.0.")))
        return
      }

      let setup: NativeGenerationSetup
      do {
        setup = try makeSetup(request: request)
      } catch {
        completion(.failure(error))
        return
      }

      let requestId = UUID().uuidString
      streamTasks[requestId] = Task { [weak self, streamHandler] in
        defer { self?.streamTasks.removeValue(forKey: requestId) }
        var toolRuntime: NativeToolRuntime?
        do {
          let runtime = try NativeToolRuntime(declarations: setup.toolDeclarations)
          toolRuntime = runtime
          let session = LanguageModelSession(
            model: setup.model,
            tools: runtime.tools,
            transcript: setup.promptContext.transcript
          )
          if !setup.toolDeclarations.isEmpty {
            do {
              let response = try await session.respond(
                to: setup.promptContext.prompt,
                options: setup.options
              )
              streamHandler?.send(NativeGenerateStreamEvent(
                requestId: requestId,
                parts: nil,
                done: true,
                response: NativeGenerateResponse(
                  parts: FoundationModelsHostApiImpl.responseParts(from: response.content),
                  finishReason: "stop",
                  errorCode: nil,
                  errorMessage: nil
                ),
                errorCode: nil,
                errorMessage: nil
              ))
            } catch let error as LanguageModelSession.ToolCallError
                where error.isNativeToolCapture {
              streamHandler?.send(NativeGenerateStreamEvent(
                requestId: requestId,
                parts: nil,
                done: true,
                response: NativeGenerateResponse(
                  parts: await runtime.capturedParts(),
                  finishReason: "tool_calls",
                  errorCode: nil,
                  errorMessage: nil
                ),
                errorCode: nil,
                errorMessage: nil
              ))
            }
            return
          }

          let stream = session.streamResponse(
            to: setup.promptContext.prompt,
            options: setup.options
          )
          var previousContent = ""
          for try await snapshot in stream {
            let content = snapshot.content
            let delta = content.hasPrefix(previousContent)
              ? String(content.dropFirst(previousContent.count))
              : content
            previousContent = content
            if delta.isEmpty { continue }
            streamHandler?.send(NativeGenerateStreamEvent(
              requestId: requestId,
              parts: [NativePart(text: delta, toolRequestJson: nil, toolResponseJson: nil)],
              done: false,
              response: nil,
              errorCode: nil,
              errorMessage: nil
            ))
          }

          let response: LanguageModelSession.Response<String>
          do {
            response = try await stream.collect()
          } catch let error as LanguageModelSession.ToolCallError
              where error.isNativeToolCapture {
            streamHandler?.send(NativeGenerateStreamEvent(
              requestId: requestId,
              parts: nil,
              done: true,
              response: NativeGenerateResponse(
                parts: await runtime.capturedParts(),
                finishReason: "tool_calls",
                errorCode: nil,
                errorMessage: nil
              ),
              errorCode: nil,
              errorMessage: nil
            ))
            return
          }
          streamHandler?.send(NativeGenerateStreamEvent(
            requestId: requestId,
            parts: nil,
            done: true,
            response: NativeGenerateResponse(
              parts: FoundationModelsHostApiImpl.responseParts(from: response.content),
              finishReason: "stop",
              errorCode: nil,
              errorMessage: nil
            ),
            errorCode: nil,
            errorMessage: nil
          ))
        } catch {
          let capturedParts = await toolRuntime?.capturedParts() ?? []
          if !capturedParts.isEmpty {
            streamHandler?.send(NativeGenerateStreamEvent(
              requestId: requestId,
              parts: nil,
              done: true,
              response: NativeGenerateResponse(
                parts: capturedParts,
                finishReason: "tool_calls",
                errorCode: nil,
                errorMessage: nil
              ),
              errorCode: nil,
              errorMessage: nil
            ))
            return
          }
          let pigeonError = FoundationModelsHostApiImpl.generationError(error)
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

  func cancelGenerateStream(requestId: String) {
    streamTasks.removeValue(forKey: requestId)?.cancel()
  }
}
