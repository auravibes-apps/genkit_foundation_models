import 'dart:convert';

import 'package:genkit/plugin.dart';

import 'foundation_models_exception.dart';
import 'pigeon/foundation_models_api.g.dart';

NativeGenerateRequest toNativeGenerateRequest(ModelRequest request) {
  _assertSupportedRequest(request);

  return NativeGenerateRequest(
    messages: request.messages
        .where((message) => message.role.value != Role.system.value)
        .map(_toNativeMessage)
        .toList(),
    systemInstruction: _extractSystemInstruction(request.messages),
    configJson: request.config == null ? null : jsonEncode(request.config),
    toolsJson: request.tools == null || request.tools!.isEmpty
        ? null
        : jsonEncode(request.tools!.map(_toolPromptSummary).toList()),
  );
}

ModelResponse toModelResponse(
  NativeGenerateResponse response, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolNames,
}) {
  if (response.errorCode != null) {
    throw FoundationModelsException(
      _toErrorCode(response.errorCode!),
      response.errorMessage ?? response.errorCode!,
    );
  }

  return ModelResponse(
    finishReason: _toFinishReason(response.finishReason),
    message: Message(
      role: Role.model,
      content: response.parts
          .expand(
            (part) => _toGenkitPart(
              part,
              allowedToolNames: allowedToolNames,
              completedToolNames: completedToolNames,
            ),
          )
          .toList(),
    ),
  );
}

ModelResponseChunk toModelResponseChunk(
  NativeGenerateStreamEvent event, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolNames,
}) {
  if (event.errorCode != null) {
    throw FoundationModelsException(
      _toErrorCode(event.errorCode!),
      event.errorMessage ?? event.errorCode!,
    );
  }

  return ModelResponseChunk(
    role: Role.model,
    content: (event.parts ?? const [])
        .expand(
          (part) => _toGenkitPart(
            part,
            allowedToolNames: allowedToolNames,
            completedToolNames: completedToolNames,
          ),
        )
        .toList(),
  );
}

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

NativeMessage _toNativeMessage(Message message) {
  return NativeMessage(
    role: message.role.value,
    parts: message.content.map(_toNativePart).toList(),
  );
}

NativePart _toNativePart(Part part) {
  final json = part.toJson();
  if (json case {'text': final String text}) {
    return NativePart(text: text);
  }
  if (json case {'toolRequest': final Map<String, dynamic> toolRequest}) {
    return NativePart(toolRequestJson: jsonEncode(toolRequest));
  }
  if (json case {'toolResponse': final Map<String, dynamic> toolResponse}) {
    return NativePart(toolResponseJson: jsonEncode(toolResponse));
  }
  _unsupported('Only text and tool message parts are supported.');
}

Map<String, dynamic> _toolPromptSummary(ToolDefinition tool) {
  return {
    'name': tool.name,
    'description': tool.description,
    if (tool.inputSchema != null) 'input': _summarizeSchema(tool.inputSchema!),
  };
}

Object? _summarizeSchema(Object? schema) {
  if (schema is! Map) return schema;

  final map = schema.cast<String, dynamic>();
  final properties = map['properties'];
  return {
    if (map['type'] != null) 'type': map['type'],
    if (map['description'] != null) 'description': map['description'],
    if (map['enum'] != null) 'enum': map['enum'],
    if (map['required'] != null) 'required': map['required'],
    if (properties is Map)
      'properties': properties.map(
        (key, value) => MapEntry(key.toString(), _summarizeSchema(value)),
      ),
    if (map['items'] != null) 'items': _summarizeSchema(map['items']),
  };
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

List<Part> _toGenkitPart(
  NativePart part, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolNames,
}) {
  if (part.text != null) {
    return _textToGenkitParts(
      part.text!,
      allowedToolNames: allowedToolNames,
      completedToolNames: completedToolNames,
    );
  }
  if (part.toolRequestJson != null) {
    return [
      _toolRequestPart(
        jsonDecode(part.toolRequestJson!) as Map<String, dynamic>,
        allowedToolNames: allowedToolNames,
        completedToolNames: completedToolNames,
      ),
    ];
  }
  if (part.toolResponseJson != null) {
    return [
      ToolResponsePart(
        toolResponse: ToolResponse.fromJson(
          jsonDecode(part.toolResponseJson!) as Map<String, dynamic>,
        ),
      ),
    ];
  }
  _unsupported('Native response part is empty.');
}

List<Part> _textToGenkitParts(
  String text, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolNames,
}) {
  final inlineToolCalls = _extractInlineToolCalls(text);
  final jsonToolCalls = inlineToolCalls == null
      ? _extractJsonToolCalls(text)
      : null;
  final extraction = inlineToolCalls ?? jsonToolCalls;
  if (extraction == null) return [TextPart(text: text)];

  final parts = <Part>[];
  if (extraction.remainingText.isNotEmpty) {
    parts.add(TextPart(text: extraction.remainingText));
  }
  parts.addAll(
    extraction.toolRequests.map(
      (toolRequest) => _toolRequestPart(
        toolRequest,
        allowedToolNames: allowedToolNames,
        completedToolNames: completedToolNames,
      ),
    ),
  );
  return parts;
}

final _inlineToolCallPattern = RegExp(
  r'<tool_call>\s*(\{.*?\})\s*</tool_call>',
  dotAll: true,
);

_ToolCallExtraction? _extractInlineToolCalls(String text) {
  final matches = _inlineToolCallPattern.allMatches(text).toList();
  if (matches.isEmpty) return null;

  final toolRequests = <Map<String, dynamic>>[];
  for (var i = 0; i < matches.length; i++) {
    final payload = matches[i].group(1);
    if (payload == null) return null;
    final decoded = _tryDecodeMap(payload);
    if (decoded == null) return null;
    toolRequests.add(_normalizeToolRequest(decoded, fallbackRef: 'call_$i'));
  }

  return _ToolCallExtraction(
    toolRequests: toolRequests,
    remainingText: text.replaceAll(_inlineToolCallPattern, '').trim(),
  );
}

_ToolCallExtraction? _extractJsonToolCalls(String text) {
  final decoded = _tryDecodeMap(_jsonPayload(text));
  if (decoded == null) return null;

  final rawRequests = switch (decoded) {
    {'toolRequests': final List requests} => requests,
    {'toolRequest': final Map request} => [request],
    _ => null,
  };
  if (rawRequests == null) return null;

  final toolRequests = <Map<String, dynamic>>[];
  for (var i = 0; i < rawRequests.length; i++) {
    final rawRequest = rawRequests[i];
    if (rawRequest is! Map) return null;
    toolRequests.add(
      _normalizeToolRequest(
        rawRequest.cast<String, dynamic>(),
        fallbackRef: 'call_$i',
      ),
    );
  }
  return _ToolCallExtraction(toolRequests: toolRequests, remainingText: '');
}

Map<String, dynamic> _normalizeToolRequest(
  Map<String, dynamic> raw, {
  required String fallbackRef,
}) {
  return {
    'ref': raw['ref'] ?? raw['id'] ?? fallbackRef,
    'name': raw['name'],
    'input': raw['input'] ?? raw['arguments'] ?? const <String, dynamic>{},
  };
}

ToolRequestPart _toolRequestPart(
  Map<String, dynamic> toolRequestJson, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolNames,
}) {
  final toolName = toolRequestJson['name'];
  if (allowedToolNames != null &&
      (toolName is! String || !allowedToolNames.contains(toolName))) {
    throw FoundationModelsException(
      FoundationModelsErrorCode.ignoredToolRequest,
      'The model requested an undeclared tool: $toolName.',
    );
  }
  if (completedToolNames != null && completedToolNames.contains(toolName)) {
    throw FoundationModelsException(
      FoundationModelsErrorCode.ignoredToolRequest,
      'The model repeated a completed tool request: $toolName.',
    );
  }
  return ToolRequestPart(toolRequest: ToolRequest.fromJson(toolRequestJson));
}

Map<String, dynamic>? _tryDecodeMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {
    return null;
  }
  return null;
}

String _jsonPayload(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('```')) return trimmed;

  final lines = trimmed.split('\n').toList();
  lines.removeAt(0);
  if (lines.isNotEmpty && lines.last.trim() == '```') {
    lines.removeLast();
  }
  return lines.join('\n').trim();
}

final class _ToolCallExtraction {
  const _ToolCallExtraction({
    required this.toolRequests,
    required this.remainingText,
  });

  final List<Map<String, dynamic>> toolRequests;
  final String remainingText;
}

FinishReason _toFinishReason(String? value) {
  return switch (value) {
    'stop' => FinishReason.stop,
    'length' => FinishReason.length,
    'blocked' => FinishReason.blocked,
    'interrupted' => FinishReason.interrupted,
    'other' => FinishReason.other,
    _ => FinishReason.unknown,
  };
}

FoundationModelsErrorCode _toErrorCode(String value) {
  return switch (value) {
    'apple_intelligence_disabled' =>
      FoundationModelsErrorCode.appleIntelligenceDisabled,
    'device_not_eligible' => FoundationModelsErrorCode.deviceNotEligible,
    'model_not_ready' => FoundationModelsErrorCode.modelNotReady,
    'foundation_models_unavailable' => FoundationModelsErrorCode.unavailable,
    'unsupported_request' => FoundationModelsErrorCode.unsupportedRequest,
    'generation_blocked' => FoundationModelsErrorCode.blocked,
    'decode_failed' => FoundationModelsErrorCode.decodeFailed,
    _ => FoundationModelsErrorCode.generationFailed,
  };
}

Never _unsupported(String message) {
  throw FoundationModelsException(
    FoundationModelsErrorCode.unsupportedRequest,
    message,
  );
}
