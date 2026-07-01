part of 'foundation_models_mapper.dart';

final class FoundationModelsStreamNormalizer {
  Iterable<ModelResponseChunk> add(
    NativeGenerateStreamEvent event, {
    Iterable<String>? allowedToolNames,
    Iterable<String>? completedToolRefs,
  }) sync* {
    if (event.errorCode != null) {
      throw FoundationModelsException(
        _toErrorCode(event.errorCode!),
        event.errorMessage ?? event.errorCode!,
      );
    }

    final content = <Part>[];
    for (final part in event.parts ?? const <NativePart>[]) {
      content.addAll(
        _toGenkitPart(
          part,
          allowedToolNames: allowedToolNames,
          completedToolRefs: completedToolRefs,
        ),
      );
    }
    final custom = _decodeJsonMap(event.customJson);

    if (content.isNotEmpty || custom != null) {
      yield ModelResponseChunk(
        role: Role.model,
        content: content,
        custom: custom,
      );
    }
  }
}
