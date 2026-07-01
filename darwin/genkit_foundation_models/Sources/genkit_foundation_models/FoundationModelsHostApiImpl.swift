import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

final class FoundationModelsHostApiImpl: FoundationModelsHostApi {
  init(streamHandler: FoundationModelsStreamHandler? = nil) {
    runner = NativeGenerationRunner(streamHandler: streamHandler)
  }

  private let runner: NativeGenerationRunner

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
    runner.generate(request: request, completion: completion)
  }

  func startGenerateStream(
    request: NativeGenerateRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    runner.startGenerateStream(request: request, completion: completion)
  }

  func cancelGenerateStream(requestId: String) throws {
    runner.cancelGenerateStream(requestId: requestId)
  }
}
