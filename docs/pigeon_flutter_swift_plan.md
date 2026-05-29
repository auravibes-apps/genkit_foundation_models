# Pigeon Plan For Flutter And Swift Integration

Checked against `pigeon` 26.3.4 docs and Flutter platform-channel docs on 2026-05-28.

This package should use Pigeon to generate the type-safe channel between Dart/Flutter and Swift. Dart stays responsible for the Genkit provider. Swift stays responsible for Apple `FoundationModels` calls. iOS and macOS should share the same Darwin Swift source instead of duplicating platform code.

## Why Pigeon

Pigeon generates type-safe Dart and host-platform code over Flutter platform channels. It removes hand-written method channel strings and reduces codec mistakes.

Supported by current Pigeon docs:

- Swift generation for iOS and macOS.
- Custom classes, nested data, and enums.
- Synchronous and `@async` Host API methods.
- Swift host errors using `PigeonError`.
- Event channel APIs on Swift, Kotlin, and Dart generators.
- Multi-instance APIs through a channel suffix.

## Package layout

Recommended files:

```text
pigeons/foundation_models_api.dart
lib/src/pigeon/foundation_models_api.g.dart
darwin/genkit_foundation_models.podspec
darwin/genkit_foundation_models/Sources/genkit_foundation_models/FoundationModelsApi.g.swift
darwin/genkit_foundation_models/Sources/genkit_foundation_models/FoundationModelsHostApiImpl.swift
darwin/genkit_foundation_models/Sources/genkit_foundation_models/GenkitFoundationModelsPlugin.swift
```

Use Flutter's shared Darwin source layout for iOS and macOS. This keeps one generated Swift API and one native implementation compiled for both Apple platforms.

## Plugin platform config

Configure `pubspec.yaml` with `sharedDarwinSource: true` for both iOS and macOS:

```yaml
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: GenkitFoundationModelsPlugin
        sharedDarwinSource: true
      macos:
        pluginClass: GenkitFoundationModelsPlugin
        sharedDarwinSource: true
```

Shared Darwin source is correct only when the Swift code either uses APIs available on both iOS and macOS or gates platform-specific code with `#if os(iOS)`, `#if os(macOS)`, and runtime availability checks.

## Add dependencies

Add Pigeon as a dev dependency:

```yaml
dev_dependencies:
  pigeon: ^26.3.4
```

Keep generated Dart and Swift files in the same package. Pigeon warns that splitting generated Dart and host code across packages can cause undefined behavior because both sides must be generated with the same Pigeon version.

## Pigeon interface draft

Create `pigeons/foundation_models_api.dart` outside `lib/`:

```dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/foundation_models_api.g.dart',
    swiftOut: 'darwin/genkit_foundation_models/Sources/genkit_foundation_models/FoundationModelsApi.g.swift',
    dartOptions: DartOptions(),
    swiftOptions: SwiftOptions(),
  ),
)
class NativeGenerateRequest {
  NativeGenerateRequest({
    required this.messages,
    this.systemInstruction,
    this.configJson,
    this.toolsJson,
  });

  List<NativeMessage> messages;
  String? systemInstruction;
  String? configJson;
  String? toolsJson;
}

class NativeMessage {
  NativeMessage({required this.role, required this.parts});

  String role;
  List<NativePart> parts;
}

class NativePart {
  NativePart({this.text, this.toolRequestJson, this.toolResponseJson});

  String? text;
  String? toolRequestJson;
  String? toolResponseJson;
}

class NativeGenerateResponse {
  NativeGenerateResponse({
    required this.parts,
    this.finishReason,
    this.errorCode,
    this.errorMessage,
  });

  List<NativePart> parts;
  String? finishReason;
  String? errorCode;
  String? errorMessage;
}

@HostApi()
abstract class FoundationModelsHostApi {
  @async
  NativeGenerateResponse generate(NativeGenerateRequest request);

  @async
  bool isAvailable();
}
```

Notes:

- Pigeon interface files should contain declarations only, not method bodies.
- Use JSON strings for config and tools initially to avoid over-modeling rapidly changing schema details.
- Replace JSON strings with typed Pigeon classes once the Genkit-to-FoundationModels mapping stabilizes.

## Generation command

Run:

```sh
dart run pigeon --input pigeons/foundation_models_api.dart
```

The single `swiftOut` file is compiled for both iOS and macOS through the shared Darwin plugin layout. Keep generated Dart and Swift outputs from the same Pigeon package version.

## Swift implementation

Implement the generated Swift protocol:

```swift
import Flutter
import FoundationModels

final class FoundationModelsHostApiImpl: FoundationModelsHostApi {
    func isAvailable(completion: @escaping (Result<Bool, Error>) -> Void) {
        // Check OS/device/model availability here.
        completion(.success(true))
    }

    func generate(
        request: NativeGenerateRequest,
        completion: @escaping (Result<NativeGenerateResponse, Error>) -> Void
    ) {
        Task {
            do {
                let session = LanguageModelSession()
                let prompt = request.messages
                    .flatMap { $0.parts }
                    .compactMap { $0.text }
                    .joined(separator: "\n")

                let nativeResponse = try await session.respond(to: prompt)
                completion(.success(NativeGenerateResponse(
                    parts: [NativePart(text: String(describing: nativeResponse), toolRequestJson: nil, toolResponseJson: nil)],
                    finishReason: "stop",
                    errorCode: nil,
                    errorMessage: nil
                )))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
```

Generated signatures can differ by Pigeon version and nullability. Treat this as shape guidance, not final compiled Swift.

## Plugin registration

Register the generated API handler in the shared Darwin plugin class:

```swift
public class GenkitFoundationModelsPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let api = FoundationModelsHostApiImpl()
        FoundationModelsHostApiSetup.setUp(binaryMessenger: messenger, api: api)
    }
}
```

For multi-instance support, use Pigeon's generated channel suffix support if the provider needs multiple independent sessions.

## Podspec shape

The shared Darwin podspec should include Swift sources from the shared package folder and declare both Flutter dependencies:

```ruby
Pod::Spec.new do |s|
  s.name = 'genkit_foundation_models'
  s.source_files = 'genkit_foundation_models/Sources/genkit_foundation_models/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '26.0'
  s.osx.deployment_target = '26.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
```

Apple `FoundationModels` is available from iOS 26.0 and macOS 26.0 in the installed Xcode 26.5 SDK, so the shared Darwin podspec must target 26.0 for both platforms.

## Dart adapter

Dart provider flow:

```dart
final api = FoundationModelsHostApi();

final nativeResponse = await api.generate(
  NativeGenerateRequest(
    messages: toNativeMessages(request.messages),
    systemInstruction: extractSystemInstruction(request.messages),
    configJson: encodeConfig(request.config),
    toolsJson: encodeTools(request.tools),
  ),
);

return toGenkitModelResponse(nativeResponse);
```

Keep the adapter pure and testable:

- `toNativeMessages(...)`
- `extractSystemInstruction(...)`
- `encodeConfig(...)`
- `encodeTools(...)`
- `toGenkitModelResponse(...)`

## Streaming plan

Implement in phases:

1. Non-streaming `generate` HostApi.
2. Availability checks.
3. Tool request/response round trip.
4. Streaming through Pigeon `@EventChannelApi` or a generated Flutter API callback.
5. Cancellation and session lifecycle.

For streaming, prefer event channels because Pigeon supports Swift event-channel APIs and Flutter platform messages remain asynchronous. Do not block a HostApi call for an entire long stream if chunks must reach Dart incrementally.

## Error mapping

Swift Host API errors become Dart `PlatformException` through Pigeon. For Swift, use `PigeonError` for structured errors.

Recommended error codes:

- `foundation_models_unavailable`
- `apple_intelligence_disabled`
- `unsupported_request`
- `tool_schema_unsupported`
- `generation_failed`
- `decode_failed`
- `cancelled`

## Verification checklist

- `dart run pigeon --input pigeons/foundation_models_api.dart` succeeds.
- Generated Dart compiles with `flutter analyze`.
- Generated Swift is under `darwin/` and included in both iOS and macOS builds.
- Plugin registration installs the HostApi handler.
- Dart `isAvailable()` returns a deterministic value on unsupported OS/devices.
- Dart `generate()` receives text from Swift on supported OS/devices.
- Pigeon generated files are regenerated together after Pigeon version changes.

## Sources

- Pigeon package page, version 26.3.4: https://pub.dev/packages/pigeon
- Flutter platform channels guide: https://docs.flutter.dev/platform-integration/platform-channels
- Flutter shared Darwin plugin pattern observed in official Flutter packages using `sharedDarwinSource: true`.
