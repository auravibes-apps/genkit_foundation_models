## 0.0.3

* Fixed streamed tool-call parsing so split `<tool_call>` tags are converted to Genkit tool requests instead of visible text.
* Added support for `genkit: ^0.14.1`.

## 0.0.2

* Added the `foundationModels` plugin facade for provider-style Genkit setup.
* Added the `FoundationModels.isAvailable()` facade and hid Pigeon transport types from the public API.
* Improved unsupported-platform handling so availability checks return `false` without exposing platform-channel details.
* Added public API documentation for pub.dev scoring.

## 0.0.1

* Initial release with Apple Foundation Models text generation for Genkit.
* Added streaming responses, multi-turn conversation support, and Genkit-owned tool loops through formatted tool-call output.
* Added shared Darwin Flutter plugin support for iOS and macOS with Swift Package Manager and CocoaPods fallback.
