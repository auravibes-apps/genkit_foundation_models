import 'dart:async';

import 'package:flutter/services.dart';

import 'foundation_models_exception.dart';
import 'pigeon/foundation_models_api.g.dart';

abstract interface class FoundationModelsApi {
  Future<bool> isAvailable();

  Future<NativeGenerateResponse> generate(NativeGenerateRequest request);

  Stream<NativeGenerateStreamEvent> streamGenerate(
    NativeGenerateRequest request,
  );
}

final class PigeonFoundationModelsApi implements FoundationModelsApi {
  PigeonFoundationModelsApi({FoundationModelsHostApi? hostApi})
    : _hostApi = hostApi ?? FoundationModelsHostApi();

  final FoundationModelsHostApi _hostApi;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _hostApi.isAvailable();
    } on PlatformException catch (error) {
      throw _foundationModelsException(error);
    }
  }

  @override
  Future<NativeGenerateResponse> generate(NativeGenerateRequest request) async {
    try {
      return await _hostApi.generate(request);
    } on PlatformException catch (error) {
      throw _foundationModelsException(error);
    }
  }

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
    'foundation_models_unavailable' => FoundationModelsErrorCode.unavailable,
    _ => FoundationModelsErrorCode.generationFailed,
  };
}

bool _isModelNotReady(PlatformException error) {
  return error.message?.toLowerCase().contains('assets are not ready') ?? false;
}
