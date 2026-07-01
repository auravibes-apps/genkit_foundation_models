# Genkit Foundation Models Example

This example is a debugging app for `genkit_foundation_models`.

Requirements:

- iOS 26.0 or macOS 26.0 target.
- Xcode SDK with `FoundationModels`.
- Apple Intelligence enabled and model assets ready on the device.

Run from this directory with a generated Flutter runner:

```sh
flutter create . --platforms=ios,macos
flutter run -d macos
```

The app demonstrates:

- streaming chat responses
- native Foundation Models tool-call capture through Genkit
- local `current_time` and todo tools
- visible tool request/result bubbles
- debug turn logs, chunk logs, errors, and copy-log support
- native reasoning/debug metadata when exposed by the bridge
- tool visibility controls: pass all tools or manually select tools
- `singlePhase` mode, which forces a final-answer pass without tools after a
  tool response

"Thinking" bubbles are UI status only. They are not model reasoning output.

Native Swift plugin changes require a full app rebuild/relaunch. Hot reload does
not reload the Foundation Models plugin code.
