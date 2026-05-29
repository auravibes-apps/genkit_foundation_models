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
  );
}

ModelResponse toModelResponse(NativeGenerateResponse response) {
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
      content: response.parts.map(_toGenkitPart).toList(),
    ),
  );
}

void _assertSupportedRequest(ModelRequest request) {
  if (request.tools != null && request.tools!.isNotEmpty) {
    _unsupported('Tool declarations are not supported yet.');
  }
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
      _unsupported('Only text message parts are supported.');
    }
  }
}

NativeMessage _toNativeMessage(Message message) {
  return NativeMessage(
    role: message.role.value,
    parts: message.content
        .map((part) => NativePart(text: part.toJson()['text'] as String))
        .toList(),
  );
}

String? _extractSystemInstruction(List<Message> messages) {
  final text = messages
      .where((message) => message.role.value == Role.system.value)
      .expand((message) => message.content)
      .map((part) => part.toJson()['text'] as String)
      .join('\n')
      .trim();

  return text.isEmpty ? null : text;
}

Part _toGenkitPart(NativePart part) {
  if (part.text != null) return TextPart(text: part.text!);
  _unsupported('Native non-text response parts are not supported yet.');
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
