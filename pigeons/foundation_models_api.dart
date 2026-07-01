import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/foundation_models_api.g.dart',
    dartPackageName: 'genkit_foundation_models',
    swiftOut:
        'darwin/genkit_foundation_models/Sources/genkit_foundation_models/FoundationModelsApi.g.swift',
    dartOptions: DartOptions(),
    swiftOptions: SwiftOptions(),
  ),
)
/// Native generation request sent from Dart to Swift.
class NativeGenerateRequest {
  NativeGenerateRequest({
    required this.messages,
    this.systemInstruction,
    this.configJson,
    this.toolsJson,
  });

  /// Ordered conversation messages to send to the native model.
  List<NativeMessage> messages;

  /// Optional system instruction used to initialize the native session.
  String? systemInstruction;

  /// JSON-encoded generation config such as temperature or token limit.
  String? configJson;

  /// JSON-encoded tool declarations for native tool capture.
  String? toolsJson;
}

/// One conversation message for the native Foundation Models bridge.
class NativeMessage {
  NativeMessage({required this.role, required this.parts});

  /// Genkit role value such as `user`, `model`, or `tool`.
  String role;

  /// Ordered message parts.
  List<NativePart> parts;
}

/// One native message or response part.
class NativePart {
  NativePart({
    this.text,
    this.toolRequestJson,
    this.toolResponseJson,
    this.reasoningText,
    this.metadataJson,
    this.customJson,
  });

  /// Plain text content.
  String? text;

  /// JSON-encoded Genkit tool request.
  String? toolRequestJson;

  /// JSON-encoded Genkit tool response.
  String? toolResponseJson;

  /// Native reasoning/debug text. Never assistant-visible response text.
  String? reasoningText;

  /// JSON-encoded metadata for this part.
  String? metadataJson;

  /// JSON-encoded custom data for this part.
  String? customJson;
}

/// Complete native generation response.
class NativeGenerateResponse {
  NativeGenerateResponse({
    required this.parts,
    this.finishReason,
    this.errorCode,
    this.errorMessage,
    this.customJson,
    this.rawJson,
  });

  /// Response parts returned by the native model bridge.
  List<NativePart> parts;

  /// Optional native finish reason.
  String? finishReason;

  /// Optional native error code.
  String? errorCode;

  /// Optional native error message.
  String? errorMessage;

  /// JSON-encoded response custom metadata.
  String? customJson;

  /// JSON-encoded raw native response/debug metadata.
  String? rawJson;
}

/// Event emitted while a native generation request is streaming.
class NativeGenerateStreamEvent {
  NativeGenerateStreamEvent({
    this.requestId,
    this.parts,
    this.done,
    this.response,
    this.errorCode,
    this.errorMessage,
    this.customJson,
  });

  /// Native stream request id used to filter shared event-channel events.
  String? requestId;

  /// Incremental response parts.
  List<NativePart>? parts;

  /// Whether this event closes the stream.
  bool? done;

  /// Final response included on the closing event.
  NativeGenerateResponse? response;

  /// Optional native stream error code.
  String? errorCode;

  /// Optional native stream error message.
  String? errorMessage;

  /// JSON-encoded stream chunk custom metadata.
  String? customJson;
}

/// Host API implemented in Swift.
@HostApi()
abstract class FoundationModelsHostApi {
  /// Generates one final response.
  @async
  NativeGenerateResponse generate(NativeGenerateRequest request);

  /// Starts a streaming generation and returns its request id.
  @async
  String startGenerateStream(NativeGenerateRequest request);

  /// Cancels a streaming generation by request id.
  void cancelGenerateStream(String requestId);

  /// Returns whether the native system model is available now.
  @async
  bool isAvailable();
}

/// Event-channel API implemented in Swift for streaming events.
@EventChannelApi()
abstract class FoundationModelsStreamApi {
  /// Broadcasts native streaming events.
  NativeGenerateStreamEvent streamEvents();
}
