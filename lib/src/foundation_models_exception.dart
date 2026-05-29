/// Stable error codes emitted by the Foundation Models provider.
enum FoundationModelsErrorCode {
  /// Apple Intelligence is disabled in system settings.
  appleIntelligenceDisabled,

  /// Current device cannot run Apple Intelligence Foundation Models.
  deviceNotEligible,

  /// Model assets are still downloading or preparing.
  modelNotReady,

  /// Foundation Models are unavailable for the current OS, locale, or session.
  unavailable,

  /// The Genkit request uses a capability this provider does not support.
  unsupportedRequest,

  /// The model requested an unavailable or already completed tool.
  ignoredToolRequest,

  /// Native safety guardrails blocked generation.
  blocked,

  /// Native request or response payload decoding failed.
  decodeFailed,

  /// Generation failed for an unclassified native reason.
  generationFailed,
}

/// Exception thrown by this package for native availability and generation failures.
final class FoundationModelsException implements Exception {
  /// Creates a provider exception with a stable [code] and human message.
  const FoundationModelsException(this.code, this.message, {this.details});

  /// Machine-readable failure category.
  final FoundationModelsErrorCode code;

  /// Short native or provider error message.
  final String message;

  /// Optional platform error details.
  final Object? details;

  /// User-facing title for this error category.
  String get title {
    return switch (code) {
      FoundationModelsErrorCode.appleIntelligenceDisabled =>
        'Apple Intelligence is disabled',
      FoundationModelsErrorCode.deviceNotEligible => 'Device is not eligible',
      FoundationModelsErrorCode.modelNotReady =>
        'Foundation model is not ready',
      FoundationModelsErrorCode.unavailable => 'Foundation Models unavailable',
      FoundationModelsErrorCode.unsupportedRequest => 'Unsupported request',
      FoundationModelsErrorCode.ignoredToolRequest => 'Ignored tool request',
      FoundationModelsErrorCode.blocked => 'Generation blocked',
      FoundationModelsErrorCode.decodeFailed => 'Native response decode failed',
      FoundationModelsErrorCode.generationFailed => 'Generation failed',
    };
  }

  /// Suggested recovery action when one is known.
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
      FoundationModelsErrorCode.ignoredToolRequest => null,
      FoundationModelsErrorCode.blocked =>
        'Try a different prompt. The system safety guardrails blocked this request.',
      FoundationModelsErrorCode.decodeFailed => null,
      FoundationModelsErrorCode.generationFailed => null,
    };
  }

  /// Combined title, message, and recovery suggestion for UI display.
  String get userMessage {
    final suggestion = recoverySuggestion;
    if (suggestion == null) return '$title: $message';
    return '$title: $message\n\n$suggestion';
  }

  @override
  String toString() => 'FoundationModelsException($code): $message';
}
