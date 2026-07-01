part of 'foundation_models_plugin.dart';

final class _FoundationModelsModelRunner {
  const _FoundationModelsModelRunner({
    required FoundationModelsApi api,
    required ModelRequest request,
    required ActionFnArg<ModelResponseChunk, ModelRequest, void> context,
  }) : _api = api,
       _request = request,
       _context = context;

  final FoundationModelsApi _api;
  final ModelRequest _request;
  final ActionFnArg<ModelResponseChunk, ModelRequest, void> _context;

  Future<ModelResponse> run() async {
    final includeTools = _includeTools(_request);
    if (_context.streamingRequested) {
      try {
        return await _streamOnce(includeTools: includeTools);
      } on FoundationModelsException catch (error) {
        if (_shouldRetryWithoutTools(_request, includeTools, error)) {
          return _streamOnce(includeTools: false);
        }
        rethrow;
      }
    }

    try {
      return await _generateOnce(includeTools: includeTools);
    } on FoundationModelsException catch (error) {
      if (_shouldRetryWithoutTools(_request, includeTools, error)) {
        return _generateOnce(includeTools: false);
      }
      rethrow;
    }
  }

  Future<ModelResponse> _generateOnce({required bool includeTools}) async {
    final nativeRequest = toNativeGenerateRequest(
      _request,
      includeTools: includeTools,
    );
    final nativeResponse = await _api.generate(nativeRequest);
    return toModelResponse(
      nativeResponse,
      allowedToolNames: _allowedToolNames(includeTools),
      completedToolRefs: _completedToolRefs(_request),
    );
  }

  Future<ModelResponse> _streamOnce({required bool includeTools}) async {
    final nativeRequest = toNativeGenerateRequest(
      _request,
      includeTools: includeTools,
    );
    final allowedToolNames = _allowedToolNames(includeTools);
    final completedToolRefs = _completedToolRefs(_request);

    NativeGenerateResponse? finalResponse;
    final streamNormalizer = FoundationModelsStreamNormalizer();
    final streamedContent = <Part>[];
    await for (final event in _api.streamGenerate(nativeRequest)) {
      if (event.errorCode != null) {
        for (final _ in streamNormalizer.add(
          event,
          allowedToolNames: allowedToolNames,
          completedToolRefs: completedToolRefs,
        )) {}
      }
      if (event.done ?? false) {
        finalResponse = event.response;
        continue;
      }
      for (final chunk in streamNormalizer.add(
        event,
        allowedToolNames: allowedToolNames,
        completedToolRefs: completedToolRefs,
      )) {
        streamedContent.addAll(chunk.content);
        _context.sendChunk(chunk);
      }
    }

    if (finalResponse == null) {
      if (streamedContent.isNotEmpty) {
        return ModelResponse(
          finishReason: FinishReason.stop,
          message: Message(role: Role.model, content: streamedContent),
        );
      }
      throw const FoundationModelsException(
        FoundationModelsErrorCode.generationFailed,
        'Native stream ended without a final response.',
      );
    }
    return toModelResponse(
      finalResponse,
      allowedToolNames: allowedToolNames,
      completedToolRefs: completedToolRefs,
    );
  }

  Iterable<String> _allowedToolNames(bool includeTools) {
    return includeTools
        ? _request.tools?.map((tool) => tool.name) ?? const <String>[]
        : const <String>[];
  }
}
