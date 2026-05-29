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

class NativeGenerateStreamEvent {
  NativeGenerateStreamEvent({
    this.requestId,
    this.parts,
    this.done,
    this.response,
    this.errorCode,
    this.errorMessage,
  });

  String? requestId;
  List<NativePart>? parts;
  bool? done;
  NativeGenerateResponse? response;
  String? errorCode;
  String? errorMessage;
}

@HostApi()
abstract class FoundationModelsHostApi {
  @async
  NativeGenerateResponse generate(NativeGenerateRequest request);

  @async
  String startGenerateStream(NativeGenerateRequest request);

  void cancelGenerateStream(String requestId);

  @async
  bool isAvailable();
}

@EventChannelApi()
abstract class FoundationModelsStreamApi {
  NativeGenerateStreamEvent streamEvents();
}
