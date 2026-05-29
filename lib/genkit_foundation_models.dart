/// Genkit provider for Apple's on-device Foundation Models.
///
/// Import this library to register the plugin, check native availability, or
/// use the generated native
/// DTOs in tests and advanced integrations.
library;

export 'src/foundation_models_api.dart';
export 'src/foundation_models_exception.dart';
export 'src/foundation_models_plugin.dart';
export 'src/pigeon/foundation_models_api.g.dart'
    show
        FoundationModelsHostApi,
        NativeGenerateRequest,
        NativeGenerateResponse,
        NativeGenerateStreamEvent,
        NativeMessage,
        NativePart,
        streamEvents;
