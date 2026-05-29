# Genkit Foundation Models Example

This example shows the text-generation MVP for `genkit_foundation_models`.

Requirements:

- iOS 26.0 or macOS 26.0 target.
- Xcode SDK with `FoundationModels`.
- Apple Intelligence enabled and model assets ready on the device.

Run from this directory with a generated Flutter runner:

```sh
flutter create . --platforms=ios,macos
flutter run -d macos
```

The package currently supports text-only generation. Streaming, media, tools, and structured output are intentionally not enabled yet.
