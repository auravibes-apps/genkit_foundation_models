import 'package:genkit/plugin.dart';

import 'foundation_models_api.dart';
import 'foundation_models_exception.dart';
import 'foundation_models_mapper.dart';
import 'pigeon/foundation_models_api.g.dart';

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
        final allowedToolNames = request.tools?.map((tool) => tool.name);
        final completedToolNames = _completedToolNames(request);
        if (context.streamingRequested) {
          NativeGenerateResponse? finalResponse;
          await for (final event in _api.streamGenerate(nativeRequest)) {
            if (event.done ?? false) {
              finalResponse = event.response;
              continue;
            }
            context.sendChunk(
              toModelResponseChunk(
                event,
                allowedToolNames: allowedToolNames,
                completedToolNames: completedToolNames,
              ),
            );
          }

          if (finalResponse == null) {
            throw const FoundationModelsException(
              FoundationModelsErrorCode.generationFailed,
              'Native stream ended without a final response.',
            );
          }
          return toModelResponse(
            finalResponse,
            allowedToolNames: allowedToolNames,
            completedToolNames: completedToolNames,
          );
        }

        final nativeResponse = await _api.generate(nativeRequest);
        return toModelResponse(
          nativeResponse,
          allowedToolNames: allowedToolNames,
          completedToolNames: completedToolNames,
        );
      },
    );
  }

  Set<String> _completedToolNames(ModelRequest request) {
    return request.messages
        .expand((message) => message.content)
        .map((part) => part.toolResponse?.name)
        .nonNulls
        .toSet();
  }

  static final ActionMetadata _metadata = modelMetadata(
    defaultModelName,
    modelInfo: ModelInfo(
      label: 'Apple Foundation Models',
      supports: {
        'multiturn': true,
        'systemRole': true,
        'media': false,
        'tools': true,
        'toolChoice': false,
        'constrained': false,
        'output': ['text'],
      },
    ),
  );
}
