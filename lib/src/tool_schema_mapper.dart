part of 'foundation_models_mapper.dart';

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
