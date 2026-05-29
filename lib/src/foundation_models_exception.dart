enum FoundationModelsErrorCode {
  appleIntelligenceDisabled,
  deviceNotEligible,
  modelNotReady,
  unavailable,
  unsupportedRequest,
  blocked,
  decodeFailed,
  generationFailed,
}

final class FoundationModelsException implements Exception {
  const FoundationModelsException(this.code, this.message, {this.details});

  final FoundationModelsErrorCode code;
  final String message;
  final Object? details;

  String get title {
    return switch (code) {
      FoundationModelsErrorCode.appleIntelligenceDisabled =>
        'Apple Intelligence is disabled',
      FoundationModelsErrorCode.deviceNotEligible => 'Device is not eligible',
      FoundationModelsErrorCode.modelNotReady =>
        'Foundation model is not ready',
      FoundationModelsErrorCode.unavailable => 'Foundation Models unavailable',
      FoundationModelsErrorCode.unsupportedRequest => 'Unsupported request',
      FoundationModelsErrorCode.blocked => 'Generation blocked',
      FoundationModelsErrorCode.decodeFailed => 'Native response decode failed',
      FoundationModelsErrorCode.generationFailed => 'Generation failed',
    };
  }

  String? get recoverySuggestion {
    return switch (code) {
      FoundationModelsErrorCode.appleIntelligenceDisabled =>
        'Enable Apple Intelligence in System Settings, then restart the app.',
      FoundationModelsErrorCode.deviceNotEligible =>
        'Run on an Apple Intelligence eligible Apple silicon device.',
      FoundationModelsErrorCode.modelNotReady =>
        'Keep the Mac online and wait for Apple Intelligence model assets to finish downloading.',
      FoundationModelsErrorCode.unavailable =>
        'Check OS version, Apple Intelligence settings, language, and model availability.',
      FoundationModelsErrorCode.unsupportedRequest => null,
      FoundationModelsErrorCode.blocked =>
        'Try a different prompt. The system safety guardrails blocked this request.',
      FoundationModelsErrorCode.decodeFailed => null,
      FoundationModelsErrorCode.generationFailed => null,
    };
  }

  String get userMessage {
    final suggestion = recoverySuggestion;
    if (suggestion == null) return '$title: $message';
    return '$title: $message\n\n$suggestion';
  }

  @override
  String toString() => 'FoundationModelsException($code): $message';
}
