part of 'foundation_models_mapper.dart';

ToolRequestPart _toolRequestPart(
  Map<String, dynamic> toolRequestJson, {
  Iterable<String>? allowedToolNames,
  Iterable<String>? completedToolRefs,
}) {
  final toolName = toolRequestJson['name'];
  if (allowedToolNames != null &&
      (toolName is! String || !allowedToolNames.contains(toolName))) {
    throw FoundationModelsException(
      FoundationModelsErrorCode.ignoredToolRequest,
      'The model requested an undeclared tool: $toolName.',
    );
  }
  final toolRef = toolRequestJson['ref'];
  if (completedToolRefs != null && completedToolRefs.contains(toolRef)) {
    throw FoundationModelsException(
      FoundationModelsErrorCode.ignoredToolRequest,
      'The model repeated a completed tool request: $toolRef.',
    );
  }
  return ToolRequestPart(toolRequest: ToolRequest.fromJson(toolRequestJson));
}
