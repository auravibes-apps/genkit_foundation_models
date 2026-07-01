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

    test('maps native reasoning without exposing response text', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              reasoningText: 'checked local context',
              metadataJson: '{"source":"native"}',
              customJson: '{"visibility":"debug"}',
            ),
          ],
          finishReason: 'stop',
          customJson: '{"turn":"final"}',
          rawJson: '{"provider":"foundation_models"}',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(ModelRequest(messages: _textMessages));

      expect(response.text, isEmpty);
      final reasoning = response.message?.content.single.reasoningPart;
      expect(reasoning?.reasoning, 'checked local context');
      expect(reasoning?.metadata, {'source': 'native'});
      expect(reasoning?.custom, {'visibility': 'debug'});
      expect(response.custom, {'turn': 'final'});
      expect(response.raw, {'provider': 'foundation_models'});
    });

    test('maps native text part metadata and custom data', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              text: 'native answer',
              metadataJson: '{"source":"native"}',
              customJson: '{"debug":true}',
            ),
          ],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(ModelRequest(messages: _textMessages));
      final textPart = response.message?.content.single.textPart;

      expect(response.text, 'native answer');
      expect(textPart?.metadata, {'source': 'native'});
      expect(textPart?.custom, {'debug': true});
    });

    test('throws decode error for invalid native metadata json', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [NativePart(reasoningText: 'hidden', metadataJson: 'nope')],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      await expectLater(
        () => model(ModelRequest(messages: _textMessages)),
        throwsA(
          isA<FoundationModelsException>().having(
            (error) => error.code,
            'code',
            FoundationModelsErrorCode.decodeFailed,
          ),
        ),
      );
    });

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

    test('streams reasoning chunks and custom metadata', () async {
      final api = _FakeFoundationModelsApi(
        streamEvents: [
          NativeGenerateStreamEvent(
            parts: [
              NativePart(reasoningText: 'thinking', customJson: '{"k":"v"}'),
            ],
            customJson: '{"chunk":1}',
          ),
          NativeGenerateStreamEvent(
            done: true,
            response: NativeGenerateResponse(
              parts: [NativePart(text: 'answer')],
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

      expect(chunks.single.custom, {'chunk': 1});
      final reasoning = chunks.single.content.single.reasoningPart;
      expect(reasoning?.reasoning, 'thinking');
      expect(reasoning?.custom, {'k': 'v'});
      expect(response.text, 'answer');
    });

    test('streams repeated identical text chunks', () async {
      final api = _FakeFoundationModelsApi(
        streamEvents: [
          NativeGenerateStreamEvent(parts: [NativePart(text: 'ha')]),
          NativeGenerateStreamEvent(parts: [NativePart(text: 'ha')]),
          NativeGenerateStreamEvent(
            done: true,
            response: NativeGenerateResponse(
              parts: [NativePart(text: 'haha')],
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

      expect(chunks.map((chunk) => chunk.content.single.text), ['ha', 'ha']);
      expect(response.message?.content.single.text, 'haha');
    });

    test('throws native errors from done stream events', () async {
      final api = _FakeFoundationModelsApi(
        streamEvents: [
          NativeGenerateStreamEvent(parts: [NativePart(text: 'partial')]),
          NativeGenerateStreamEvent(
            done: true,
            errorCode: 'generation_blocked',
            errorMessage: 'blocked',
          ),
        ],
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      await expectLater(
        model(ModelRequest(messages: _textMessages), onChunk: (_) {}),
        throwsA(
          isA<FoundationModelsException>().having(
            (error) => error.code,
            'code',
            FoundationModelsErrorCode.blocked,
          ),
        ),
      );
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

    test('maps native captured tool calls without prompt tags', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              toolRequestJson:
                  '{"ref":"call_0","name":"lookup","input":{"q":"aura"}}',
            ),
          ],
          finishReason: 'tool_calls',
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
      expect(response.finishReason.value, 'stop');
      final toolRequest = response.message?.content.single.toolRequest;
      expect(toolRequest?.ref, 'call_0');
      expect(toolRequest?.name, 'lookup');
      expect(toolRequest?.input, {'q': 'aura'});
    });

    test('maps multiple native captured tool calls in order', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              toolRequestJson:
                  '{"ref":"call_0","name":"first","input":{"q":"a"}}',
            ),
            NativePart(
              toolRequestJson:
                  '{"ref":"call_1","name":"second","input":{"q":"b"}}',
            ),
          ],
          finishReason: 'tool_calls',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(
        ModelRequest(
          messages: _textMessages,
          tools: [
            ToolDefinition(name: 'first', description: 'First'),
            ToolDefinition(name: 'second', description: 'Second'),
          ],
        ),
      );

      final toolRequests = response.message?.content
          .map((part) => part.toolRequest)
          .nonNulls
          .toList();
      expect(toolRequests?.map((request) => request.ref), ['call_0', 'call_1']);
      expect(toolRequests?.map((request) => request.name), ['first', 'second']);
      expect(toolRequests?.map((request) => request.input), [
        {'q': 'a'},
        {'q': 'b'},
      ]);
    });

    test('extracts fenced json array tool calls from native text', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              text: '''```json
[{"name":"web_search","arguments":{"query":"pokemon"}}]
```''',
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
            ToolDefinition(name: 'web_search', description: 'Search web'),
          ],
        ),
      );

      expect(response.text, isEmpty);
      final toolRequest = response.message?.content.single.toolRequest;
      expect(toolRequest?.name, 'web_search');
      expect(toolRequest?.input, {'query': 'pokemon'});
    });

    test('lets Genkit execute model-requested tools', () async {
      final api = _FakeFoundationModelsApi(
        responses: [
          NativeGenerateResponse(
            parts: [
              NativePart(
                toolRequestJson:
                    '{"ref":"call-1","name":"lookup","input":{"q":"aura"}}',
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

    test('allows the same tool after a prior tool response', () async {
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

      final response = await model(
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
      );

      expect(response.message?.content.single.toolRequest?.ref, 'call-2');
      expect(
        response.message?.content.single.toolRequest?.name,
        'current_time',
      );
    });

    test('does not repeat completed tool request refs', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              toolRequestJson:
                  '{"ref":"call-1","name":"current_time","input":{}}',
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

    test('allows repeated tool input with a new ref', () async {
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

      final response = await model(
        ModelRequest(
          messages: [
            ..._textMessages,
            Message(
              role: Role.model,
              content: [
                ToolRequestPart(
                  toolRequest: ToolRequest(
                    ref: 'call-1',
                    name: 'current_time',
                    input: {},
                  ),
                ),
              ],
            ),
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
      );

      expect(response.message?.content.single.toolRequest?.ref, 'call-2');
      expect(
        response.message?.content.single.toolRequest?.name,
        'current_time',
      );
    });

    test('allows repeated tool input after a new user message', () async {
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

      final response = await model(
        ModelRequest(
          messages: [
            Message(
              role: Role.user,
              content: [TextPart(text: 'What time is it?')],
            ),
            Message(
              role: Role.model,
              content: [
                ToolRequestPart(
                  toolRequest: ToolRequest(
                    ref: 'call-1',
                    name: 'current_time',
                    input: {},
                  ),
                ),
              ],
            ),
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
            Message(
              role: Role.user,
              content: [TextPart(text: 'What time is it now?')],
            ),
          ],
          tools: [
            ToolDefinition(
              name: 'current_time',
              description: 'Returns current time',
            ),
          ],
        ),
      );

      expect(response.message?.content.single.toolRequest?.ref, 'call-2');
      expect(
        response.message?.content.single.toolRequest?.name,
        'current_time',
      );
    });

    test('omits tools after tool responses in single-phase mode', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [NativePart(text: 'It is now.')],
          finishReason: 'stop',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(
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
          config: {'foundationModelsToolLoopMode': 'singlePhase'},
          tools: [
            ToolDefinition(
              name: 'current_time',
              description: 'Returns current time',
            ),
          ],
        ),
      );

      expect(api.lastRequest?.toolsJson, isNull);
      expect(response.text, 'It is now.');
    });

    test('keeps tools available on a new user turn by default', () async {
      final api = _FakeFoundationModelsApi(
        response: NativeGenerateResponse(
          parts: [
            NativePart(
              toolRequestJson:
                  '{"ref":"call-2","name":"current_time","input":{}}',
            ),
          ],
          finishReason: 'tool_calls',
        ),
      );
      final plugin = FoundationModelsPlugin.testing(api: api);
      final model = plugin.model(FoundationModelsPlugin.defaultModelName);

      final response = await model(
        ModelRequest(
          messages: [
            Message(
              role: Role.user,
              content: [TextPart(text: 'What time is it?')],
            ),
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
            Message(
              role: Role.model,
              content: [TextPart(text: 'It is now.')],
            ),
            Message(
              role: Role.user,
              content: [TextPart(text: 'What time is it now?')],
            ),
          ],
          tools: [
            ToolDefinition(
              name: 'current_time',
              description: 'Returns current time',
            ),
          ],
        ),
      );

      expect(api.lastRequest?.toolsJson, isNotNull);
      expect(response.message?.content.single.toolRequest?.ref, 'call-2');
    });

    test(
      'retries final tool-response generation without tools on failure',
      () async {
        final api = _FakeFoundationModelsApi(
          generateResults: [
            const FoundationModelsException(
              FoundationModelsErrorCode.generationFailed,
              'native tool follow-up failed',
            ),
            NativeGenerateResponse(
              parts: [NativePart(text: 'todo-1: Try current_time')],
              finishReason: 'stop',
            ),
          ],
        );
        final plugin = FoundationModelsPlugin.testing(api: api);
        final model = plugin.model(FoundationModelsPlugin.defaultModelName);

        final response = await model(
          ModelRequest(
            messages: [
              Message(
                role: Role.user,
                content: [TextPart(text: 'What are my todos?')],
              ),
              Message(
                role: Role.tool,
                content: [
                  ToolResponsePart(
                    toolResponse: ToolResponse(
                      ref: 'call-1',
                      name: 'todo_read',
                      output: {
                        'todos': [
                          {'id': 'todo-1', 'name': 'Try current_time'},
                        ],
                      },
                    ),
                  ),
                ],
              ),
            ],
            tools: [
              ToolDefinition(name: 'todo_read', description: 'Reads todos'),
            ],
          ),
        );

        expect(api.requests, hasLength(2));
        expect(api.requests.first.toolsJson, isNotNull);
        expect(api.requests.last.toolsJson, isNull);
        expect(response.text, 'todo-1: Try current_time');
      },
    );

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
      await expectUnsupported(
        ModelRequest(
          messages: [
            Message(
              role: Role.system,
              content: [
                ToolRequestPart(
                  toolRequest: ToolRequest(
                    ref: 'call-1',
                    name: 'current_time',
                    input: {},
                  ),
                ),
              ],
            ),
            ..._textMessages,
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
    List<Object>? generateResults,
    List<NativeGenerateStreamEvent>? streamEvents,
  }) : generateResults =
           generateResults ??
           (responses ??
                   [
                     response ??
                         NativeGenerateResponse(
                           parts: [NativePart(text: 'ok')],
                           finishReason: 'stop',
                         ),
                   ])
               .cast<Object>(),
       streamEvents = streamEvents ?? const [];

  final List<Object> generateResults;
  final List<NativeGenerateStreamEvent> streamEvents;
  NativeGenerateRequest? lastRequest;
  final requests = <NativeGenerateRequest>[];
  bool streamed = false;

  @override
  Future<NativeGenerateResponse> generate(NativeGenerateRequest request) async {
    lastRequest = request;
    requests.add(request);
    final result = generateResults[requests.length - 1];
    if (result is Exception) throw result;
    return result as NativeGenerateResponse;
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
