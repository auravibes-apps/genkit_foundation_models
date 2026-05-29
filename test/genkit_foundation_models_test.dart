import 'package:flutter/services.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_foundation_models/genkit_foundation_models.dart';
import 'package:test/test.dart';

void main() {
  group('FoundationModelsPlugin', () {
    test('lists a text-only Genkit model action', () async {
      final plugin = FoundationModelsPlugin(api: _FakeFoundationModelsApi());

      final actions = await plugin.list();

      expect(plugin.name, FoundationModelsPlugin.providerName);
      expect(actions, hasLength(1));
      expect(actions.single.actionType, 'model');
      expect(actions.single.name, FoundationModelsPlugin.defaultModelName);

      final model = actions.single.metadata['model'] as Map<String, dynamic>;
      final supports = model['supports'] as Map<String, dynamic>;
      expect(supports['multiturn'], isTrue);
      expect(supports['systemRole'], isTrue);
      expect(supports['media'], isFalse);
      expect(supports['tools'], isFalse);
      expect(supports['constrained'], isFalse);
      expect(supports['output'], ['text']);
    });

    test('resolves only the default Foundation Models action', () {
      final plugin = FoundationModelsPlugin(api: _FakeFoundationModelsApi());

      expect(
        plugin.resolve('model', FoundationModelsPlugin.defaultModelName),
        isA<Model>(),
      );
      expect(
        plugin.resolve('model', FoundationModelsPlugin.systemLanguageModelName),
        isA<Model>(),
      );
      expect(plugin.resolve('model', 'other/model'), isNull);
      expect(
        plugin.resolve('tool', FoundationModelsPlugin.defaultModelName),
        isNull,
      );
    });

    test(
      'maps text messages to native request and response to Genkit text',
      () async {
        final api = _FakeFoundationModelsApi(
          response: NativeGenerateResponse(
            parts: [NativePart(text: 'native answer')],
            finishReason: 'stop',
          ),
        );
        final plugin = FoundationModelsPlugin(api: api);
        final model = plugin.model(FoundationModelsPlugin.defaultModelName);

        final response = await model(
          ModelRequest(
            messages: [
              Message(
                role: Role.system,
                content: [TextPart(text: 'Be terse')],
              ),
              Message(
                role: Role.user,
                content: [TextPart(text: 'Hello')],
              ),
            ],
            config: {'temperature': 0.2},
          ),
        );

        expect(api.lastRequest?.systemInstruction, 'Be terse');
        expect(api.lastRequest?.messages, hasLength(1));
        expect(api.lastRequest?.messages.single.role, 'user');
        expect(api.lastRequest?.messages.single.parts.single.text, 'Hello');
        expect(api.lastRequest?.configJson, '{"temperature":0.2}');
        expect(response.finishReason.value, 'stop');
        expect(response.message?.role.value, 'model');
        expect(response.message?.content.single.text, 'native answer');
      },
    );

    test('works through Genkit plugin model lookup', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [NativePart(text: 'generated through registry')],
          finishReason: 'stop',
        ),
      );
      final genkit = Genkit(
        isDevEnv: false,
        plugins: [FoundationModelsPlugin(api: api)],
        model: modelRef(FoundationModelsPlugin.defaultModelName),
      );
      addTearDown(genkit.shutdown);

      final response = await genkit.generate(prompt: 'Hello');

      expect(response.text, 'generated through registry');
      expect(api.lastRequest?.messages.single.parts.single.text, 'Hello');
    });

    test('fails early for unsupported request features', () async {
      final plugin = FoundationModelsPlugin(api: _FakeFoundationModelsApi());
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      Future<void> expectUnsupported(ModelRequest request) async {
        await expectLater(
          model(request),
          throwsA(
            isA<FoundationModelsException>().having(
              (error) => error.code,
              'code',
              FoundationModelsErrorCode.unsupportedRequest,
            ),
          ),
        );
      }

      await expectUnsupported(
        ModelRequest(
          messages: [
            Message(
              role: Role.user,
              content: [
                MediaPart(media: Media(url: 'data:image/png;base64,abc')),
              ],
            ),
          ],
        ),
      );
      await expectUnsupported(
        ModelRequest(
          messages: _textMessages,
          tools: [ToolDefinition(name: 'lookup', description: 'Lookup data')],
        ),
      );
      await expectUnsupported(
        ModelRequest(
          messages: _textMessages,
          output: OutputConfig(format: 'json', schema: {'type': 'object'}),
        ),
      );
      await expectUnsupported(
        ModelRequest(
          messages: _textMessages,
          docs: [
            DocumentData(content: [TextPart(text: 'doc')]),
          ],
        ),
      );
    });

    test('maps native availability errors to typed exceptions', () async {
      Future<void> expectNativeError(
        PlatformException platformException,
        FoundationModelsErrorCode code,
      ) async {
        final api = PigeonFoundationModelsApi(
          hostApi: _ThrowingFoundationModelsHostApi(platformException),
        );

        await expectLater(
          api.generate(NativeGenerateRequest(messages: [])),
          throwsA(
            isA<FoundationModelsException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
      }

      await expectNativeError(
        PlatformException(
          code: 'apple_intelligence_disabled',
          message: 'Apple Intelligence is not enabled.',
        ),
        FoundationModelsErrorCode.appleIntelligenceDisabled,
      );
      await expectNativeError(
        PlatformException(
          code: 'model_not_ready',
          message: 'FoundationModels assets are not ready.',
        ),
        FoundationModelsErrorCode.modelNotReady,
      );
      await expectNativeError(
        PlatformException(
          code: 'foundation_models_unavailable',
          message: 'FoundationModels assets are not ready.',
        ),
        FoundationModelsErrorCode.modelNotReady,
      );
    });
  });
}

final _textMessages = [
  Message(
    role: Role.user,
    content: [TextPart(text: 'Hello')],
  ),
];

final class _FakeFoundationModelsApi implements FoundationModelsApi {
  _FakeFoundationModelsApi({NativeGenerateResponse? response})
    : response =
          response ??
          NativeGenerateResponse(
            parts: [NativePart(text: 'ok')],
            finishReason: 'stop',
          );

  final NativeGenerateResponse response;
  NativeGenerateRequest? lastRequest;

  @override
  Future<NativeGenerateResponse> generate(NativeGenerateRequest request) async {
    lastRequest = request;
    return response;
  }

  @override
  Future<bool> isAvailable() async => true;
}

final class _ThrowingFoundationModelsHostApi extends FoundationModelsHostApi {
  _ThrowingFoundationModelsHostApi(this.error);

  final PlatformException error;

  @override
  Future<NativeGenerateResponse> generate(NativeGenerateRequest request) {
    throw error;
  }

  @override
  Future<bool> isAvailable() {
    throw error;
  }
}
