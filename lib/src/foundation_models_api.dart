import 'package:flutter/services.dart';

import 'foundation_models_exception.dart';
import 'pigeon/foundation_models_api.g.dart';

abstract interface class FoundationModelsApi {
  Future<bool> isAvailable();

  Future<NativeGenerateResponse> generate(NativeGenerateRequest request);
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
