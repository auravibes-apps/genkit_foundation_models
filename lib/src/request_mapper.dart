part of 'foundation_models_mapper.dart';

NativeGenerateRequest toNativeGenerateRequest(
  ModelRequest request, {
  bool includeTools = true,
}) {
  _assertSupportedRequest(request);

  return NativeGenerateRequest(
    messages: request.messages
        .where((message) => message.role.value != Role.system.value)
        .map(_toNativeMessage)
        .toList(),
    systemInstruction: _extractSystemInstruction(request.messages),
    configJson: request.config == null ? null : jsonEncode(request.config),
    toolsJson: !includeTools || request.tools == null || request.tools!.isEmpty
        ? null
        : jsonEncode(request.tools!.map(_toolPromptSummary).toList()),
  );
}

NativeMessage _toNativeMessage(Message message) {
  return NativeMessage(
    role: message.role.value,
    parts: message.content.map(_toNativePart).toList(),
  );
}

NativePart _toNativePart(Part part) {
  final json = part.toJson();
  switch (_nativePartKind(json)) {
    case _NativePartKind.text:
      return NativePart(text: json['text'] as String);
    case _NativePartKind.toolRequest:
      return NativePart(
        toolRequestJson: jsonEncode(
          json['toolRequest'] as Map<String, dynamic>,
        ),
      );
    case _NativePartKind.toolResponse:
      return NativePart(
        toolResponseJson: jsonEncode(
          json['toolResponse'] as Map<String, dynamic>,
        ),
      );
    case null:
      _unsupported('Only text and tool message parts are supported.');
  }
}

String? _extractSystemInstruction(List<Message> messages) {
  final text = messages
      .where((message) => message.role.value == Role.system.value)
      .expand((message) => message.content)
      .map((part) => part.toJson()['text'])
      .whereType<String>()
      .join('\n')
      .trim();

  return text.isEmpty ? null : text;
}
