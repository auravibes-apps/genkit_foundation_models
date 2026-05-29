import 'dart:async';

import 'package:flutter/services.dart';

import 'foundation_models_exception.dart';
import 'pigeon/foundation_models_api.g.dart';

/// Internal Dart-facing interface for the native Apple Foundation Models bridge.
///
/// Implement this in tests to avoid platform channels, or use
/// [PigeonFoundationModelsApi] to call the Swift implementation.
abstract interface class FoundationModelsApi {
  /// Returns whether the system language model is currently available.
  Future<bool> isAvailable();

  /// Generates one complete native response for [request].
  Future<NativeGenerateResponse> generate(NativeGenerateRequest request);

  /// Streams native response events for [request].
  Stream<NativeGenerateStreamEvent> streamGenerate(
    NativeGenerateRequest request,
  );
}

/// Internal platform-channel backed implementation of [FoundationModelsApi].
///
/// This class wraps the Pigeon-generated [FoundationModelsHostApi] and maps
/// platform errors into [FoundationModelsException].
final class PigeonFoundationModelsApi implements FoundationModelsApi {
  /// Creates an API wrapper around [hostApi], or the default platform channel.
  PigeonFoundationModelsApi({FoundationModelsHostApi? hostApi})
    : _hostApi = hostApi ?? FoundationModelsHostApi();

  final FoundationModelsHostApi _hostApi;

  /// Returns whether Apple Foundation Models can be used on this device now.
  @override
  Future<bool> isAvailable() async {
    try {
      return await _hostApi.isAvailable();
    } on PlatformException catch (error) {
      if (_isMissingPlatformChannel(error)) return false;
      throw _foundationModelsException(error);
    }
  }

  /// Sends [request] to the host platform and waits for the final response.
  @override
  Future<NativeGenerateResponse> generate(NativeGenerateRequest request) async {
    try {
      return await _hostApi.generate(request);
    } on PlatformException catch (error) {
      throw _foundationModelsException(error);
    }
  }

  /// Starts native streaming and yields events for this request only.
  @override
  Stream<NativeGenerateStreamEvent> streamGenerate(
    NativeGenerateRequest request,
  ) async* {
    final events = streamEvents();
    final controller = StreamController<NativeGenerateStreamEvent>();
    final subscription = events.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    final requestId = await _startGenerateStream(request);

    try {
      await for (final event in controller.stream) {
        if (event.requestId != requestId) continue;
        yield event;
        if (event.done ?? false) return;
      }
    } finally {
      await subscription.cancel();
      await controller.close();
      await _cancelGenerateStream(requestId);
    }
  }

  Future<String> _startGenerateStream(NativeGenerateRequest request) async {
    try {
      return await _hostApi.startGenerateStream(request);
    } on PlatformException catch (error) {
      throw _foundationModelsException(error);
    }
  }

  Future<void> _cancelGenerateStream(String requestId) async {
    try {
      await _hostApi.cancelGenerateStream(requestId);
    } on PlatformException catch (error) {
      throw _foundationModelsException(error);
    }
  }
}

FoundationModelsException _foundationModelsException(PlatformException error) {
  return FoundationModelsException(
    _errorCode(error),
    error.message ?? error.code,
    details: error.details,
  );
}

FoundationModelsErrorCode _errorCode(PlatformException error) {
  return switch (error.code) {
    'apple_intelligence_disabled' =>
      FoundationModelsErrorCode.appleIntelligenceDisabled,
    'device_not_eligible' => FoundationModelsErrorCode.deviceNotEligible,
    'model_not_ready' => FoundationModelsErrorCode.modelNotReady,
    'unsupported_request' => FoundationModelsErrorCode.unsupportedRequest,
    'generation_blocked' => FoundationModelsErrorCode.blocked,
    'decode_failed' => FoundationModelsErrorCode.decodeFailed,
    'generation_failed' => FoundationModelsErrorCode.generationFailed,
    'foundation_models_unavailable' when _isModelNotReady(error) =>
      FoundationModelsErrorCode.modelNotReady,
    'channel-error' => FoundationModelsErrorCode.unavailable,
    'missing-plugin' => FoundationModelsErrorCode.unavailable,
    'MissingPluginException' => FoundationModelsErrorCode.unavailable,
    'foundation_models_unavailable' => FoundationModelsErrorCode.unavailable,
    _ => FoundationModelsErrorCode.generationFailed,
  };
}

bool _isMissingPlatformChannel(PlatformException error) {
  return error.code == 'channel-error' ||
      error.code == 'missing-plugin' ||
      error.code == 'MissingPluginException';
}

bool _isModelNotReady(PlatformException error) {
  return error.message?.toLowerCase().contains('assets are not ready') ?? false;
}
