part of 'foundation_models_mapper.dart';

void _assertSupportedRequest(ModelRequest request) {
  if (request.toolChoice != null) {
    _unsupported('Tool choice is not supported yet.');
  }
  if (request.output != null) {
    _unsupported('Structured or constrained output is not supported yet.');
  }
  if (request.docs != null) {
    _unsupported('Document context is not supported yet.');
  }

  for (final message in request.messages) {
    for (final part in message.content) {
      final json = part.toJson();
      if (json.containsKey('text')) continue;
      if (json.containsKey('toolRequest')) continue;
      if (json.containsKey('toolResponse')) continue;
      _unsupported('Only text and tool message parts are supported.');
    }
  }
}

Never _unsupported(String message) {
  throw FoundationModelsException(
    FoundationModelsErrorCode.unsupportedRequest,
    message,
  );
}
