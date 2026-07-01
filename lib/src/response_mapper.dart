part of 'foundation_models_mapper.dart';

ModelResponse toModelResponse(
  NativeGenerateResponse response, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolRefs,
}) {
  if (response.errorCode != null) {
    throw FoundationModelsException(
      _toErrorCode(response.errorCode!),
      response.errorMessage ?? response.errorCode!,
    );
  }

  return ModelResponse(
    finishReason: _toFinishReason(response.finishReason),
    custom: _decodeJsonMap(response.customJson),
    raw: _decodeJsonMap(response.rawJson),
    message: Message(
      role: Role.model,
      content: response.parts
          .expand(
            (part) => _toGenkitPart(
              part,
              allowedToolNames: allowedToolNames,
              completedToolRefs: completedToolRefs,
            ),
          )
          .toList(),
    ),
  );
}

ModelResponseChunk toModelResponseChunk(
  NativeGenerateStreamEvent event, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolRefs,
}) {
  if (event.errorCode != null) {
    throw FoundationModelsException(
      _toErrorCode(event.errorCode!),
      event.errorMessage ?? event.errorCode!,
    );
  }

  return ModelResponseChunk(
    role: Role.model,
    custom: _decodeJsonMap(event.customJson),
    content: (event.parts ?? const [])
        .expand(
          (part) => _toGenkitPart(
            part,
            allowedToolNames: allowedToolNames,
            completedToolRefs: completedToolRefs,
          ),
        )
        .toList(),
  );
}

List<Part> _toGenkitPart(
  NativePart part, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolRefs,
}) {
  final metadata = _decodeJsonMap(part.metadataJson);
  final custom = _decodeJsonMap(part.customJson);
  if (part.text != null) {
    return _textToGenkitParts(
      part.text!,
      allowedToolNames: allowedToolNames,
      completedToolRefs: completedToolRefs,
    ).map((part) {
      if (part is TextPart) {
        return TextPart(text: part.text, metadata: metadata, custom: custom);
      }
      return part;
    }).toList();
  }
  if (part.reasoningText != null) {
    return [
      ReasoningPart(
        reasoning: part.reasoningText!,
        metadata: metadata,
        custom: custom,
      ),
    ];
  }
  if (part.toolRequestJson != null) {
    return [
      _toolRequestPart(
        jsonDecode(part.toolRequestJson!) as Map<String, dynamic>,
        allowedToolNames: allowedToolNames,
        completedToolRefs: completedToolRefs,
      ),
    ];
  }
  if (part.toolResponseJson != null) {
    return [
      ToolResponsePart(
        toolResponse: ToolResponse.fromJson(
          jsonDecode(part.toolResponseJson!) as Map<String, dynamic>,
        ),
        metadata: metadata,
        custom: custom,
      ),
    ];
  }
  _unsupported('Native response part is empty.');
}

Map<String, dynamic>? _decodeJsonMap(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {
    throw FoundationModelsException(
      FoundationModelsErrorCode.decodeFailed,
      'Native metadata JSON could not be decoded.',
    );
  }
  throw FoundationModelsException(
    FoundationModelsErrorCode.decodeFailed,
    'Native metadata JSON must be an object.',
  );
}

FinishReason _toFinishReason(String? value) {
  return switch (value) {
    'stop' => FinishReason.stop,
    'length' => FinishReason.length,
    'blocked' => FinishReason.blocked,
    'interrupted' => FinishReason.interrupted,
    'tool_calls' => FinishReason.stop,
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
