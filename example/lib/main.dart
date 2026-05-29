import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_foundation_models/genkit_foundation_models.dart';

void main() {
  runApp(const FoundationModelsExampleApp());
}

final class FoundationModelsExampleApp extends StatelessWidget {
  const FoundationModelsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foundation Models Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const GeneratePage(),
    );
  }
}

final class GeneratePage extends StatefulWidget {
  const GeneratePage({super.key});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

final class _GeneratePageState extends State<GeneratePage> {
  final _messageController = TextEditingController(
    text:
        'Use the current_time tool, then answer normally with a two sentence welcome message for a Genkit plugin.',
  );
  final _scrollController = ScrollController();
  late final Tool<Map<String, dynamic>?, Map<String, String>> _currentTimeTool;
  late final Genkit _genkit;

  final _items = <_ChatItem>[];
  var _messages = <Message>[];
  bool? _isAvailable;
  var _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _currentTimeTool = Tool<Map<String, dynamic>?, Map<String, String>>(
      name: 'current_time',
      description: 'Returns the current local date and time.',
      fn: (input, _) async {
        final output = _currentTimeToolOutput();
        _addItem(_ChatItem.tool('current_time(${input ?? {}}) -> $output'));
        return output;
      },
    );
    _genkit = Genkit(
      isDevEnv: false,
      plugins: [foundationModels],
      model: modelRef(FoundationModelsPlugin.defaultModelName),
    );
    unawaited(_checkAvailability());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    unawaited(_genkit.shutdown());
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    try {
      final isAvailable = await FoundationModels.isAvailable();
      if (!mounted) return;
      setState(() => _isAvailable = isAvailable);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAvailable = false);
      _addItem(_ChatItem.error(_errorMessage(error)));
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    final requestMessages = [
      ..._messages,
      Message(
        role: Role.user,
        content: [TextPart(text: text)],
      ),
    ];

    _messageController.clear();
    final statusItem = _ChatItem.thinking('Thinking...');
    var assistantItem = _ChatItem.assistant('');
    setState(() {
      _isGenerating = true;
      _items.add(_ChatItem.user(text));
      _items.add(statusItem);
    });
    _scrollToBottom();

    try {
      final stream = _genkit.generateStream(
        messages: requestMessages,
        config: {'temperature': 0.2, 'maxOutputTokens': 256},
        tools: [_currentTimeTool],
      );
      await for (final chunk in stream) {
        if (!mounted || chunk.text.isEmpty) continue;
        setState(() {
          if (_items.contains(statusItem)) {
            _items.remove(statusItem);
          }
          if (!_items.contains(assistantItem)) {
            _items.add(assistantItem);
          }
          assistantItem.text += chunk.text;
        });
        _scrollToBottom();
      }

      final response = await stream.onResult;
      if (!mounted) return;
      setState(() {
        _messages = response.messages;
        if (_items.contains(statusItem)) {
          _items.remove(statusItem);
        }
        if (response.text.isNotEmpty) {
          if (!_items.contains(assistantItem)) {
            _items.add(assistantItem);
          }
          assistantItem.text = response.text;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items.remove(statusItem);
        if (assistantItem.text.isEmpty) {
          _items.remove(assistantItem);
        }
        if (_isIgnoredToolRequest(error)) {
          assistantItem = _ChatItem.assistant(
            'I ignored a tool request that was not available. I can only use the tools listed by the app, like current_time.',
          );
          _items.add(assistantItem);
        } else {
          _items.add(_ChatItem.error(_errorMessage(error)));
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = switch (_isAvailable) {
      true => 'Available',
      false => 'Unavailable',
      null => 'Checking...',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Foundation Models')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Apple Foundation Models: $availability'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _items.length,
              itemBuilder: (context, index) => _ChatBubble(item: _items[index]),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => unawaited(_sendMessage()),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Message',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isGenerating ? null : _sendMessage,
                  child: Text(_isGenerating ? 'Sending...' : 'Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addItem(_ChatItem item) {
    if (!mounted) return;
    setState(() => _items.add(item));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _errorMessage(Object error) {
    if (error is FoundationModelsException) return error.userMessage;
    return error.toString();
  }

  bool _isIgnoredToolRequest(Object error) {
    return error is FoundationModelsException &&
        error.code == FoundationModelsErrorCode.ignoredToolRequest;
  }

  Map<String, String> _currentTimeToolOutput() {
    final now = DateTime.now();
    return {'currentTime': now.toIso8601String(), 'timeZone': now.timeZoneName};
  }
}

final class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.item});

  final _ChatItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = item.type == _ChatItemType.user;
    final colorScheme = theme.colorScheme;
    final background = switch (item.type) {
      _ChatItemType.user => colorScheme.primaryContainer,
      _ChatItemType.assistant => colorScheme.surfaceContainerHighest,
      _ChatItemType.tool => colorScheme.tertiaryContainer,
      _ChatItemType.thinking => colorScheme.secondaryContainer,
      _ChatItemType.error => colorScheme.errorContainer,
    };
    final label = switch (item.type) {
      _ChatItemType.user => 'You',
      _ChatItemType.assistant => 'Assistant',
      _ChatItemType.tool => 'Tool call',
      _ChatItemType.thinking => 'Thinking',
      _ChatItemType.error => 'Error',
    };

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              SelectableText(item.text.isEmpty ? 'Streaming...' : item.text),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ChatItem {
  _ChatItem(this.type, this.text);

  factory _ChatItem.user(String text) => _ChatItem(_ChatItemType.user, text);
  factory _ChatItem.assistant(String text) =>
      _ChatItem(_ChatItemType.assistant, text);
  factory _ChatItem.tool(String text) => _ChatItem(_ChatItemType.tool, text);
  factory _ChatItem.thinking(String text) =>
      _ChatItem(_ChatItemType.thinking, text);
  factory _ChatItem.error(String text) => _ChatItem(_ChatItemType.error, text);

  final _ChatItemType type;
  String text;
}

enum _ChatItemType { user, assistant, tool, thinking, error }
