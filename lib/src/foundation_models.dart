import 'foundation_models_api.dart';

/// Convenience facade for Apple Foundation Models availability checks.
///
/// This API is safe to call from apps that also target Android, web, Windows,
/// or Linux. Unsupported platforms return `false` instead of exposing Pigeon
/// transport errors.
abstract final class FoundationModels {
  /// Returns whether Apple's system language model can be used right now.
  static Future<bool> isAvailable() {
    return PigeonFoundationModelsApi().isAvailable();
  }
}
