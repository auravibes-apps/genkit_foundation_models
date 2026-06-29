import 'package:genkit/plugin.dart';
import 'package:meta/meta.dart';

import 'foundation_models_api.dart';
import 'foundation_models_exception.dart';
import 'foundation_models_mapper.dart';
import 'pigeon/foundation_models_api.g.dart';

/// Ready-to-register Genkit plugin for Apple Foundation Models.
///
/// Use this in `Genkit(plugins: [foundationModels])` for the normal package
/// setup, matching other Genkit provider packages.
final foundationModels = FoundationModelsPlugin();

/// Genkit plugin that exposes Apple's system language model.
///
/// Register this plugin with `Genkit(plugins: [foundationModels])` and
/// use [defaultModelName] as the model reference.
final class FoundationModelsPlugin extends GenkitPlugin {
  /// Creates a plugin backed by the default native bridge.
  FoundationModelsPlugin() : _api = PigeonFoundationModelsApi();

  /// Creates a plugin backed by [api] for tests.
  @visibleForTesting
  FoundationModelsPlugin.testing({required FoundationModelsApi api})
    : _api = api;

  /// Genkit provider namespace for this plugin.
  static const providerName = 'foundationModels';

  /// Provider-local model id for Apple's system language model.
  static const systemLanguageModelName = 'system-language-model';

  /// Full Genkit model name exposed by this provider.
  static const defaultModelName = '$providerName/system-language-model';

  final FoundationModelsApi _api;

  /// Provider name used by Genkit registry lookup.
  @override
  String get name => providerName;

  /// Lists the model actions exposed by this plugin.
  @override
  Future<List<ActionMetadata>> list() async => [_metadata];

  /// Resolves the Apple system language model action.
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
          final streamNormalizer = FoundationModelsStreamNormalizer();
          final streamedContent = <Part>[];
          await for (final event in _api.streamGenerate(nativeRequest)) {
            if (event.errorCode != null) {
              for (final _ in streamNormalizer.add(
                event,
                allowedToolNames: allowedToolNames,
                completedToolNames: completedToolNames,
              )) {}
            }
            if (event.done ?? false) {
              finalResponse = event.response;
              continue;
            }
            for (final chunk in streamNormalizer.add(
              event,
              allowedToolNames: allowedToolNames,
              completedToolNames: completedToolNames,
            )) {
              streamedContent.addAll(chunk.content);
              context.sendChunk(chunk);
            }
          }

          final bufferedChunk = streamNormalizer.flush(
            allowedToolNames: allowedToolNames,
            completedToolNames: completedToolNames,
          );
          if (bufferedChunk != null) {
            streamedContent.addAll(bufferedChunk.content);
            context.sendChunk(bufferedChunk);
          }

          if (finalResponse == null) {
            if (streamedContent.isNotEmpty) {
              return ModelResponse(
                finishReason: FinishReason.stop,
                message: Message(role: Role.model, content: streamedContent),
              );
            }
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
