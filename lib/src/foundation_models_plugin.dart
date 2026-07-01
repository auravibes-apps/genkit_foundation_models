import 'package:genkit/plugin.dart';
import 'package:meta/meta.dart';

import 'foundation_models_api.dart';
import 'foundation_models_exception.dart';
import 'foundation_models_mapper.dart';
import 'pigeon/foundation_models_api.g.dart';

part 'model_runner.dart';
part 'tool_loop_policy.dart';

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
        return _FoundationModelsModelRunner(
          api: _api,
          request: request,
          context: context,
        ).run();
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
        'tools': true,
        'toolChoice': false,
        'constrained': false,
        'output': ['text'],
      },
    ),
  );
}
