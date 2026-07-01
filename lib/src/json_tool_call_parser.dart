part of 'foundation_models_mapper.dart';

List<Part> _textToGenkitParts(
  String text, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolRefs,
}) {
  final extraction = _extractJsonToolCalls(text);
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
        completedToolRefs: completedToolRefs,
      ),
    ),
  );
  return parts;
}

_ToolCallExtraction? _extractJsonToolCalls(String text) {
  final decoded = _tryDecode(_jsonPayload(text));
  if (decoded == null) return null;

  final rawRequests = switch (decoded) {
    final List requests => requests,
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

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
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
