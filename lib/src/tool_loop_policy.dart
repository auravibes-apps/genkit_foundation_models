part of 'foundation_models_plugin.dart';

Set<String> _completedToolRefs(ModelRequest request) {
  return request.messages
      .expand((message) => message.content)
      .map((part) => part.toolResponse?.ref)
      .nonNulls
      .toSet();
}

bool _includeTools(ModelRequest request) {
  if (request.tools == null || request.tools!.isEmpty) return false;
  if (request.config?['foundationModelsToolLoopMode'] == 'chained') {
    return true;
  }
  if (request.config?['foundationModelsToolLoopMode'] == 'singlePhase') {
    return !_latestMessageIsToolResponse(request);
  }
  return !_latestMessageIsToolResponse(request);
}

bool _latestMessageIsToolResponse(ModelRequest request) {
  if (request.messages.isEmpty) return false;
  return request.messages.last.content.any((part) => part.toolResponse != null);
}

bool _shouldRetryWithoutTools(
  ModelRequest request,
  bool includeTools,
  FoundationModelsException error,
) {
  return includeTools &&
      error.code == FoundationModelsErrorCode.generationFailed &&
      _latestMessageIsToolResponse(request);
}
