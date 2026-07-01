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
      if (_nativePartKind(part.toJson()) != null) continue;
      _unsupported('Only text and tool message parts are supported.');
    }
  }
}

_NativePartKind? _nativePartKind(Map<String, dynamic> json) {
  if (json case {'text': String _}) return _NativePartKind.text;
  if (json case {'toolRequest': Map<String, dynamic> _}) {
    return _NativePartKind.toolRequest;
  }
  if (json case {'toolResponse': Map<String, dynamic> _}) {
    return _NativePartKind.toolResponse;
  }
  return null;
}

enum _NativePartKind { text, toolRequest, toolResponse }

Never _unsupported(String message) {
  throw FoundationModelsException(
    FoundationModelsErrorCode.unsupportedRequest,
    message,
  );
}
