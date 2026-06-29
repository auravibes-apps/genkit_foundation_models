import 'package:flutter/services.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_foundation_models/genkit_foundation_models.dart';
import 'package:genkit_foundation_models/src/foundation_models_api.dart';
import 'package:genkit_foundation_models/src/pigeon/foundation_models_api.g.dart';
import 'package:test/test.dart';

void main() {
  group('FoundationModelsPlugin', () {
    test('lists a text-only Genkit model action', () async {
      final plugin = FoundationModelsPlugin.testing(
        api: _FakeFoundationModelsApi(),
      );

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
      expect(supports['tools'], isTrue);
      expect(supports['constrained'], isFalse);
      expect(supports['output'], ['text']);
    });

    test('resolves only the default Foundation Models action', () {
      final plugin = FoundationModelsPlugin.testing(
        api: _FakeFoundationModelsApi(),
      );

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
        final plugin = FoundationModelsPlugin.testing(api: api);
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
        plugins: [FoundationModelsPlugin.testing(api: api)],
        model: modelRef(FoundationModelsPlugin.defaultModelName),
      );
      addTearDown(genkit.shutdown);

      final response = await genkit.generate(prompt: 'Hello');

      expect(response.text, 'generated through registry');
      expect(api.lastRequest?.messages.single.parts.single.text, 'Hello');
    });

    test('streams native text chunks through Genkit model chunks', () async {
      final api = _FakeFoundationModelsApi(
        streamEvents: [
          NativeGenerateStreamEvent(parts: [NativePart(text: 'hel')]),
          NativeGenerateStreamEvent(parts: [NativePart(text: 'lo')]),
          NativeGenerateStreamEvent(
            done: true,
            response: NativeGenerateResponse(
              parts: [NativePart(text: 'hello')],
              finishReason: 'stop',
            ),
          ),
        ],
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);
      final chunks = <ModelResponseChunk>[];

      final response = await model(
        ModelRequest(messages: _textMessages),
        onChunk: chunks.add,
      );

      expect(api.streamed, isTrue);
      expect(chunks.map((chunk) => chunk.content.single.text), ['hel', 'lo']);
      expect(chunks.every((chunk) => chunk.role?.value == 'model'), isTrue);
      expect(response.message?.content.single.text, 'hello');
    });

    test('streams split inline tool calls as tool request chunks', () async {
      final inlineToolCall =
          '<tool_call>{"name":"native_url","arguments":{"input":{"url":"https://example.com"}}}</tool_call>';
      final api = _FakeFoundationModelsApi(
        streamEvents: [
          NativeGenerateStreamEvent(parts: [NativePart(text: '<tool_')]),
          NativeGenerateStreamEvent(
            parts: [
              NativePart(
                text:
                    'call>{"name":"native_url","arguments":{"input":{"url":"https://example.com"}}}',
              ),
            ],
          ),
          NativeGenerateStreamEvent(parts: [NativePart(text: '</tool_call>')]),
          NativeGenerateStreamEvent(
            done: true,
            response: NativeGenerateResponse(
              parts: [NativePart(text: inlineToolCall)],
              finishReason: 'stop',
            ),
          ),
        ],
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);
      final chunks = <ModelResponseChunk>[];

      final response = await model(
        ModelRequest(
          messages: _textMessages,
          tools: [ToolDefinition(name: 'native_url', description: 'Open URL')],
        ),
        onChunk: chunks.add,
      );

      expect(
        chunks.expand((chunk) => chunk.content).map((part) => part.text),
        isNot(contains(contains('tool_call'))),
      );
      final streamedToolRequests = chunks
          .expand((chunk) => chunk.content)
          .map((part) => part.toolRequest)
          .nonNulls;
      expect(streamedToolRequests.single.name, 'native_url');
      expect(response.text, isEmpty);
      expect(response.message?.content.single.toolRequest?.name, 'native_url');
    });

    test('maps Genkit tool declarations and native tool requests', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              toolRequestJson:
                  '{"ref":"call-1","name":"lookup","input":{"q":"aura"}}',
            ),
          ],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(
        ModelRequest(
          messages: _textMessages,
          tools: [
            ToolDefinition(
              name: 'lookup',
              description: 'Lookup data',
              inputSchema: {
                'type': 'object',
                'properties': {
                  'q': {'type': 'string'},
                },
                'required': ['q'],
              },
            ),
          ],
        ),
      );

      expect(api.lastRequest?.toolsJson, contains('"name":"lookup"'));
      final toolRequest = response.message?.content.single.toolRequest;
      expect(toolRequest?.ref, 'call-1');
      expect(toolRequest?.name, 'lookup');
      expect(toolRequest?.input, {'q': 'aura'});
    });

    test('extracts tagged tool calls from native text responses', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              text:
                  '<tool_call>{"name":"lookup","arguments":{"q":"aura"}}</tool_call>',
            ),
          ],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(
        ModelRequest(
          messages: _textMessages,
          tools: [ToolDefinition(name: 'lookup', description: 'Lookup data')],
        ),
      );

      expect(response.text, isEmpty);
      final toolRequest = response.message?.content.single.toolRequest;
      expect(toolRequest?.name, 'lookup');
      expect(toolRequest?.input, {'q': 'aura'});
    });

    test('extracts multiple tagged tool calls from native text responses', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              text:
                  '<tool_call>{"name":"first","arguments":{"q":"a"}}</tool_call>'
                  '<tool_call>{"name":"second","arguments":{"q":"b"}}</tool_call>',
            ),
          ],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(
        ModelRequest(
          messages: _textMessages,
          tools: [
            ToolDefinition(name: 'first', description: 'First lookup'),
            ToolDefinition(name: 'second', description: 'Second lookup'),
          ],
        ),
      );

      expect(response.text, isEmpty);
      final toolRequests = response.message?.content
          .map((part) => part.toolRequest)
          .nonNulls
          .toList();
      expect(toolRequests?.map((request) => request.name), ['first', 'second']);
      expect(toolRequests?.map((request) => request.input), [
        {'q': 'a'},
        {'q': 'b'},
      ]);
    });

    test(
      'extracts native url tool calls from final inline text responses',
      () async {
        final api = _FakeFoundationModelsApi(
          response: NativeGenerateResponse(
            parts: [
              NativePart(
                text:
                    '<tool_call>{"name":"native_url","arguments":{"input":{"url":"https://example.com"}}}</tool_call>',
              ),
            ],
            finishReason: 'stop',
          ),
        );
        final plugin = FoundationModelsPlugin.testing(api: api);
        final model = plugin.model(FoundationModelsPlugin.defaultModelName);

        final response = await model(
          ModelRequest(
            messages: _textMessages,
            tools: [
              ToolDefinition(name: 'native_url', description: 'Open URL'),
            ],
          ),
        );

        expect(response.text, isEmpty);
        expect(response.text, isNot(contains('<tool_call>')));
        final toolRequest = response.message?.content.single.toolRequest;
        expect(toolRequest?.name, 'native_url');
        expect(toolRequest?.input, {
          'input': {'url': 'https://example.com'},
        });
      },
    );

    test('keeps invalid inline tool call json as text', () async {
      const invalidToolCall = '<tool_call>{not json}</tool_call>';
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [NativePart(text: invalidToolCall)],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(ModelRequest(messages: _textMessages));

      expect(response.message?.content.single.text, invalidToolCall);
      expect(response.text, invalidToolCall);
    });

    test('strips tagged tool calls from visible native text', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              text:
                  'Checking. <tool_call>{"name":"lookup","arguments":{"q":"aura"}}</tool_call>',
            ),
          ],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(
        ModelRequest(
          messages: _textMessages,
          tools: [ToolDefinition(name: 'lookup', description: 'Lookup data')],
        ),
      );

      expect(response.text, 'Checking.');
      expect(response.message?.content.last.toolRequest?.name, 'lookup');
    });

    test('lets Genkit execute model-requested tools', () async {
      final api = _FakeFoundationModelsApi(
        responses: [
          NativeGenerateResponse(
            parts: [
              NativePart(
                text:
                    '<tool_call>{"id":"call-1","name":"lookup","arguments":{"q":"aura"}}</tool_call>',
              ),
            ],
            finishReason: 'stop',
          ),
          NativeGenerateResponse(
            parts: [NativePart(text: 'Tool result used.')],
            finishReason: 'stop',
          ),
        ],
      );
      final genkit = Genkit(
        isDevEnv: false,
        plugins: [FoundationModelsPlugin.testing(api: api)],
        model: modelRef(FoundationModelsPlugin.defaultModelName),
      );
      addTearDown(genkit.shutdown);
      var toolInput = <String, dynamic>{};
      final tool = Tool<Map<String, dynamic>, Map<String, String>>(
        name: 'lookup',
        description: 'Lookup data',
        fn: (input, _) async {
          toolInput = input;
          return {'answer': 'AURA'};
        },
      );

      final response = await genkit.generate(prompt: 'Hello', tools: [tool]);

      expect(response.text, 'Tool result used.');
      expect(toolInput, {'q': 'aura'});
      expect(api.requests, hasLength(2));
      expect(api.requests.last.messages.last.role, 'tool');
      expect(
        api.requests.last.messages.last.parts.single.toolResponseJson,
        isNotNull,
      );
    });

    test(
      'does not forward undeclared native tool requests to Genkit',
      () async {
        final api = _FakeFoundationModelsApi(
          response: NativeGenerateResponse(
            parts: [
              NativePart(
                toolRequestJson:
                    '{"ref":"call-1","name":"text_generator","input":{}}',
              ),
            ],
            finishReason: 'stop',
          ),
        );
        final genkit = Genkit(
          isDevEnv: false,
          plugins: [FoundationModelsPlugin.testing(api: api)],
          model: modelRef(FoundationModelsPlugin.defaultModelName),
        );
        addTearDown(genkit.shutdown);
        final tool = Tool<Map<String, dynamic>, Map<String, String>>(
          name: 'current_time',
          description: 'Returns the current local date and time.',
          fn: (_, _) async => {'currentTime': 'now'},
        );

        await expectLater(
          genkit.generate(prompt: 'Hello', tools: [tool]),
          throwsA(
            isA<FoundationModelsException>().having(
              (error) => error.code,
              'code',
              FoundationModelsErrorCode.ignoredToolRequest,
            ),
          ),
        );
      },
    );

    test('does not repeat completed tool requests', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              toolRequestJson:
                  '{"ref":"call-2","name":"current_time","input":{}}',
            ),
          ],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      await expectLater(
        model(
          ModelRequest(
            messages: [
              ..._textMessages,
              Message(
                role: Role.tool,
                content: [
                  ToolResponsePart(
                    toolResponse: ToolResponse(
                      ref: 'call-1',
                      name: 'current_time',
                      output: {'currentTime': 'now'},
                    ),
                  ),
                ],
              ),
            ],
            tools: [
              ToolDefinition(
                name: 'current_time',
                description: 'Returns current time',
              ),
            ],
          ),
        ),
        throwsA(
          isA<FoundationModelsException>().having(
            (error) => error.code,
            'code',
            FoundationModelsErrorCode.ignoredToolRequest,
          ),
        ),
      );
    });

    test('fails early for unsupported request features', () async {
      final plugin = FoundationModelsPlugin.testing(
        api: _FakeFoundationModelsApi(),
      );
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

    test('returns unavailable on platforms without a native channel', () async {
      final api = PigeonFoundationModelsApi(
        hostApi: _ThrowingFoundationModelsHostApi(
          PlatformException(
            code: 'channel-error',
            message: 'Unable to establish connection on channel.',
          ),
        ),
      );

      expect(await api.isAvailable(), isFalse);
      await expectLater(
        api.generate(NativeGenerateRequest(messages: [])),
        throwsA(
          isA<FoundationModelsException>().having(
            (error) => error.code,
            'code',
            FoundationModelsErrorCode.unavailable,
          ),
        ),
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
  _FakeFoundationModelsApi({
    NativeGenerateResponse? response,
    List<NativeGenerateResponse>? responses,
    List<NativeGenerateStreamEvent>? streamEvents,
  }) : responses =
           responses ??
           [
             response ??
                 NativeGenerateResponse(
                   parts: [NativePart(text: 'ok')],
                   finishReason: 'stop',
                 ),
           ],
       streamEvents = streamEvents ?? const [];

  final List<NativeGenerateResponse> responses;
  final List<NativeGenerateStreamEvent> streamEvents;
  NativeGenerateRequest? lastRequest;
  final requests = <NativeGenerateRequest>[];
  bool streamed = false;

  @override
  Future<NativeGenerateResponse> generate(NativeGenerateRequest request) async {
    lastRequest = request;
    requests.add(request);
    return responses[requests.length - 1];
  }

  @override
  Stream<NativeGenerateStreamEvent> streamGenerate(
    NativeGenerateRequest request,
  ) async* {
    lastRequest = request;
    streamed = true;
    for (final event in streamEvents) {
      yield event;
    }
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
  Future<String> startGenerateStream(NativeGenerateRequest request) {
    throw error;
  }

  @override
  Future<void> cancelGenerateStream(String requestId) {
    throw error;
  }

  @override
  Future<bool> isAvailable() {
    throw error;
  }
}
