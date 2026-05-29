import 'package:genkit/plugin.dart';

import 'foundation_models_api.dart';
import 'foundation_models_exception.dart';
import 'foundation_models_mapper.dart';

final class FoundationModelsPlugin extends GenkitPlugin {
  FoundationModelsPlugin({FoundationModelsApi? api})
    : _api = api ?? PigeonFoundationModelsApi();

  static const providerName = 'foundationModels';
  static const systemLanguageModelName = 'system-language-model';
  static const defaultModelName = '$providerName/system-language-model';

  final FoundationModelsApi _api;

  @override
  String get name => providerName;

  @override
  Future<List<ActionMetadata>> list() async => [_metadata];

  @override
  Action? resolve(String actionType, String name) {
    if (actionType != 'model') return null;
    if (name != systemLanguageModelName && name != defaultModelName) {
      return null;
    }

    return Model(
      name: defaultModelName,
      metadata: _metadata.metadata,
      fn: (request, context) async {
        if (request == null) {
          throw const FoundationModelsException(
            FoundationModelsErrorCode.unsupportedRequest,
            'ModelRequest is required.',
          );
        }
        final nativeRequest = toNativeGenerateRequest(request);
        final nativeResponse = await _api.generate(nativeRequest);
        return toModelResponse(nativeResponse);
      },
    );
  }

  static final ActionMetadata _metadata = modelMetadata(
    defaultModelName,
    modelInfo: ModelInfo(
      label: 'Apple Foundation Models',
      supports: {
        'multiturn': true,
        'systemRole': true,
        'media': false,
        'tools': false,
        'toolChoice': false,
        'constrained': false,
        'output': ['text'],
      },
    ),
  );
}
