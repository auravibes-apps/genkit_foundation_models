import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_foundation_models/genkit_foundation_models.dart';
import 'package:schemantic/schemantic.dart';

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
  late final Tool<Map<String, dynamic>?, Map<String, dynamic>> _currentTimeTool;
  late final List<Tool> _tools;
  late final Genkit _genkit;

  final _items = <_ChatItem>[];
  final _todos = <_TodoItem>[
    _TodoItem(id: 'todo-1', name: 'Try current_time'),
    _TodoItem(id: 'todo-2', name: 'Ask the model to edit todos'),
  ];
  var _messages = <Message>[];
  var _nextTodoId = 3;
  _ChatItem? _activeThinkingItem;
  bool? _isAvailable;
  var _isGenerating = false;
  var _showDebug = true;
  var _showErrors = true;
  var _singlePhaseToolLoop = false;
  var _useAllTools = true;
  var _manualToolNames = <String>{};

  @override
  void initState() {
    super.initState();
    _currentTimeTool = Tool<Map<String, dynamic>?, Map<String, dynamic>>(
      name: 'current_time',
      description: 'Returns the current local date and time.',
      fn: (input, _) async {
        _setThinking('Calling current_time...');
        final output = _currentTimeToolOutput();
        _addItem(_ChatItem.tool('current_time(${input ?? {}}) -> $output'));
        return output;
      },
    );
    _tools = [
      _currentTimeTool,
      Tool<Map<String, dynamic>?, Map<String, dynamic>>(
        name: 'todo_read',
        description: 'Reads all todos with id, name, and done state.',
        fn: (_, _) async => _todoRead(),
      ),
      Tool<Map<String, dynamic>, Map<String, dynamic>>(
        name: 'todo_add',
        description: 'Adds a todo. Input: {"name":"todo name"}.',
        inputSchema: _todoNameSchema,
        fn: (input, _) async => _todoAdd(input),
      ),
      Tool<Map<String, dynamic>, Map<String, dynamic>>(
        name: 'todo_remove',
        description: 'Removes a todo by id. Input: {"id":"todo-id"}.',
        inputSchema: _todoIdSchema,
        fn: (input, _) async => _todoRemove(input),
      ),
      Tool<Map<String, dynamic>, Map<String, dynamic>>(
        name: 'todo_mark_done',
        description: 'Marks a todo as done by id. Input: {"id":"todo-id"}.',
        inputSchema: _todoIdSchema,
        fn: (input, _) async => _todoSetDone(input, done: true),
      ),
      Tool<Map<String, dynamic>, Map<String, dynamic>>(
        name: 'todo_mark_not_done',
        description: 'Marks a todo as not done by id. Input: {"id":"todo-id"}.',
        inputSchema: _todoIdSchema,
        fn: (input, _) async => _todoSetDone(input, done: false),
      ),
      Tool<Map<String, dynamic>, Map<String, dynamic>>(
        name: 'todo_update_name',
        description:
            'Renames a todo by id. Input: {"id":"todo-id","name":"new name"}.',
        inputSchema: _todoRenameSchema,
        fn: (input, _) async => _todoUpdateName(input),
      ),
    ];
    _manualToolNames = _tools.map((tool) => tool.name).toSet();
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
    final modelMessages = [
      Message(
        role: Role.system,
        content: [TextPart(text: _toolPolicy)],
      ),
      ...requestMessages,
    ];

    _messageController.clear();
    final thinkingItem = _ChatItem.thinking('Thinking...');
    var assistantItem = _ChatItem.assistant('');
    setState(() {
      _isGenerating = true;
      _items.add(_ChatItem.user(text));
      _activeThinkingItem = thinkingItem;
      _items.add(thinkingItem);
    });
    _scrollToBottom();

    try {
      var turnMessages = modelMessages;
      final activeTools = _activeTools;
      _addItem(
        _ChatItem.debug(
          'Exposed tools: ${activeTools.map((tool) => tool.name).join(', ')}',
        ),
      );
      for (var turn = 1; turn <= 50; turn++) {
        _addItem(
          _ChatItem.debug('Turn $turn: ${turnMessages.length} messages'),
        );
        final stream = _genkit.generateStream(
          messages: turnMessages,
          config: {
            'temperature': 0.2,
            'maxOutputTokens': 256,
            if (_singlePhaseToolLoop)
              'foundationModelsToolLoopMode': 'singlePhase',
          },
          tools: activeTools,
          returnToolRequests: true,
        );
        await for (final chunk in stream) {
          if (!mounted) return;
          _logChunk(turn, chunk);
          if (chunk.text.isEmpty) continue;
          setState(() {
            _removeThinkingItem();
            if (!_items.contains(assistantItem)) {
              _items.add(assistantItem);
            }
            assistantItem.text += chunk.text;
          });
          _scrollToBottom();
        }

        final response = await stream.onResult;
        if (!mounted) return;
        _logResponseDebug(turn, response);
        _addItem(
          _ChatItem.debug(
            'Turn $turn result: ${response.toolRequests.length} tool requests, ${response.text.length} text chars',
          ),
        );
        final responseMessage = response.message;
        if (responseMessage == null) break;
        final toolRequests = response.toolRequests;
        if (toolRequests.isEmpty) {
          setState(() {
            _messages = [
              ...turnMessages.where(
                (message) => message.role.value != Role.system.value,
              ),
              responseMessage,
            ];
            _removeThinkingItem();
            if (response.text.isNotEmpty) {
              if (!_items.contains(assistantItem)) {
                _items.add(assistantItem);
              }
              assistantItem.text = response.text;
            }
          });
          return;
        }

        final toolResponses = <Part>[];
        for (final toolRequest in toolRequests) {
          _addItem(
            _ChatItem.debug(
              'Turn $turn tool request: ${toolRequest.name} ref=${toolRequest.ref} input=${toolRequest.input}',
            ),
          );
          final output = await _runToolRequest(toolRequest);
          toolResponses.add(
            ToolResponsePart(
              toolResponse: ToolResponse(
                ref: toolRequest.ref,
                name: toolRequest.name,
                output: output,
              ),
            ),
          );
        }
        turnMessages = [
          ...turnMessages,
          responseMessage,
          Message(role: Role.tool, content: toolResponses),
        ];
      }
      throw StateError('Debug loop reached 50 turns. See turn debug bubbles.');
    } catch (error, stackTrace) {
      if (!mounted) return;
      _logError(error, stackTrace);
      setState(() {
        _removeThinkingItem();
        if (assistantItem.text.isEmpty) {
          _items.remove(assistantItem);
        }
        if (_isIgnoredToolRequest(error)) {
          assistantItem = _ChatItem.assistant(
            _ignoredToolRequestMessage(error),
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
    final visibleItems = _items.where(_isVisible).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Foundation Models')),
      body: Column(
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Apple Foundation Models: $availability'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _items.isEmpty ? null : _copyLog,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy log'),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Debug'),
                          selected: _showDebug,
                          onSelected: (value) =>
                              setState(() => _showDebug = value),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Errors'),
                          selected: _showErrors,
                          onSelected: (value) =>
                              setState(() => _showErrors = value),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Single phase'),
                          selected: _singlePhaseToolLoop,
                          onSelected: (value) =>
                              setState(() => _singlePhaseToolLoop = value),
                        ),
                      ],
                    ),
                  ),
                  _TodoPanel(todos: _todos),
                  _ToolScopePanel(
                    useAllTools: _useAllTools,
                    toolNames: _tools.map((tool) => tool.name).toList(),
                    selectedToolNames: _activeToolNames,
                    manualToolNames: _manualToolNames,
                    onUseAllToolsChanged: (value) =>
                        setState(() => _useAllTools = value),
                    onManualToolToggled: (toolName, selected) => setState(() {
                      if (selected) {
                        _manualToolNames.add(toolName);
                      } else {
                        _manualToolNames.remove(toolName);
                      }
                    }),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: visibleItems.length,
              itemBuilder: (context, index) =>
                  _ChatBubble(item: visibleItems[index]),
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

  void _setThinking(String text) {
    if (!mounted) return;
    setState(() {
      final item = _activeThinkingItem;
      if (item != null && _items.contains(item)) {
        item.text = text;
        return;
      }
      final nextItem = _ChatItem.thinking(text);
      _activeThinkingItem = nextItem;
      _items.add(nextItem);
    });
    _scrollToBottom();
  }

  void _removeThinkingItem() {
    final item = _activeThinkingItem;
    if (item == null) return;
    _items.remove(item);
    _activeThinkingItem = null;
  }

  Future<void> _copyLog() async {
    final log = _items
        .map((item) => '[${item.label}] ${item.text}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: log));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Log copied')));
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

  void _logError(Object error, StackTrace stackTrace) {
    final details = switch (error) {
      FoundationModelsException(:final code, :final message, :final details) =>
        'code: $code\nmessage: $message\ndetails: $details',
      _ => error.toString(),
    };
    debugPrint('Foundation Models example error:\n$details\n$stackTrace');
    _addItem(_ChatItem.debug('$details\n\n$stackTrace'));
  }

  void _logChunk(int turn, GenerateResponseChunk<dynamic> chunk) {
    final toolRequests = chunk.content
        .map((part) => part.toolRequest)
        .nonNulls
        .toList();
    final reasoning = chunk.content
        .map((part) => part.reasoning)
        .nonNulls
        .join('\n');
    if (toolRequests.isEmpty && chunk.text.isEmpty && reasoning.isEmpty) {
      if (chunk.rawChunk.custom == null) return;
    }
    _addItem(
      _ChatItem.debug(
        [
          'Turn $turn chunk: ${toolRequests.length} tool requests, ${chunk.text.length} text chars',
          if (reasoning.isNotEmpty) 'reasoning: $reasoning',
          if (chunk.rawChunk.custom != null)
            'custom: ${jsonEncode(chunk.rawChunk.custom)}',
        ].join('\n'),
      ),
    );
  }

  void _logResponseDebug(int turn, GenerateResponse response) {
    final reasoning =
        response.message?.content
            .map((part) => part.reasoning)
            .nonNulls
            .join('\n') ??
        '';
    final custom = response.custom;
    final raw = response.raw;
    if (reasoning.isEmpty && custom == null && raw == null) return;
    _addItem(
      _ChatItem.debug(
        [
          'Turn $turn native debug metadata',
          if (reasoning.isNotEmpty) 'reasoning: $reasoning',
          if (custom != null) 'custom: ${jsonEncode(custom)}',
          if (raw != null) 'raw: ${jsonEncode(raw)}',
        ].join('\n'),
      ),
    );
  }

  bool _isVisible(_ChatItem item) {
    return switch (item.type) {
      _ChatItemType.debug => _showDebug,
      _ChatItemType.error => _showErrors,
      _ => true,
    };
  }

  bool _isIgnoredToolRequest(Object error) {
    return error is FoundationModelsException &&
        error.code == FoundationModelsErrorCode.ignoredToolRequest;
  }

  String _ignoredToolRequestMessage(Object error) {
    if (error is FoundationModelsException) return error.userMessage;
    return 'Ignored tool request.';
  }

  Map<String, dynamic> _currentTimeToolOutput() {
    final now = DateTime.now();
    return {'currentTime': now.toIso8601String(), 'timeZone': now.timeZoneName};
  }

  Future<Map<String, dynamic>> _runToolRequest(ToolRequest request) async {
    final output = switch (request.name) {
      'current_time' => _currentTimeToolOutput(),
      'todo_read' => _todoRead(),
      'todo_add' => _todoAdd(request.input),
      'todo_remove' => _todoRemove(request.input),
      'todo_mark_done' => _todoSetDone(request.input, done: true),
      'todo_mark_not_done' => _todoSetDone(request.input, done: false),
      'todo_update_name' => _todoUpdateName(request.input),
      _ => {'error': 'Unknown tool ${request.name}'},
    };
    _addItem(
      _ChatItem.tool('${request.name}(${request.input ?? {}}) -> $output'),
    );
    return output;
  }

  List<Tool> get _activeTools {
    final names = _activeToolNames;
    return _tools.where((tool) => names.contains(tool.name)).toList();
  }

  Set<String> get _activeToolNames =>
      _useAllTools ? _tools.map((tool) => tool.name).toSet() : _manualToolNames;

  Map<String, dynamic> _todoRead() {
    return {'todos': _todos.map((todo) => todo.toJson()).toList()};
  }

  Map<String, dynamic> _todoAdd(Map<String, dynamic>? input) {
    final name = _requiredText(input, 'name', 'todo_add');
    final todo = _TodoItem(id: 'todo-${_nextTodoId++}', name: name);
    setState(() => _todos.add(todo));
    return {'todo': todo.toJson()};
  }

  Map<String, dynamic> _todoRemove(Map<String, dynamic>? input) {
    final id = _requiredText(input, 'id', 'todo_remove');
    final index = _todos.indexWhere((todo) => todo.id == id);
    if (index == -1) return {'error': 'Todo not found: $id'};
    final removed = _todos.removeAt(index);
    setState(() {});
    return {'removed': removed.toJson(), ..._todoRead()};
  }

  Map<String, dynamic> _todoSetDone(
    Map<String, dynamic>? input, {
    required bool done,
  }) {
    final todo = _todoById(
      input,
      done ? 'todo_mark_done' : 'todo_mark_not_done',
    );
    setState(() => todo.done = done);
    return {'todo': todo.toJson()};
  }

  Map<String, dynamic> _todoUpdateName(Map<String, dynamic>? input) {
    final todo = _todoById(input, 'todo_update_name');
    final name = _requiredText(input, 'name', 'todo_update_name');
    setState(() => todo.name = name);
    return {'todo': todo.toJson()};
  }

  _TodoItem _todoById(Map<String, dynamic>? input, String toolName) {
    final id = _requiredText(input, 'id', toolName);
    return _todos.firstWhere(
      (todo) => todo.id == id,
      orElse: () => throw ArgumentError('$toolName could not find $id.'),
    );
  }

  String _requiredText(
    Map<String, dynamic>? input,
    String key,
    String toolName,
  ) {
    final value = input?[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw ArgumentError('$toolName requires input.$key.');
    }
    return value;
  }
}

const _toolPolicy = '''
This is a debug app for a Genkit plugin.
Use tools only when the user's request explicitly asks for them or cannot be answered without them.
For read-only todo questions, call todo_read and then answer. Do not modify todos.
Call todo write tools only when the user explicitly asks to add, remove, mark, rename, or update a todo.
After a tool result is enough to answer the user's request, answer normally in prose.
Use todo_read before changing a todo if you do not know its id.
If a tool returns an error, do not retry the same failed call. Change the input, choose a different relevant tool, or answer from the transcript.
''';

final _todoNameSchema = SchemanticType.from<Map<String, dynamic>>(
  jsonSchema: {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'description': 'Todo name.', 'minLength': 1},
    },
    'required': ['name'],
  },
  parse: (json) => Map<String, dynamic>.from(json as Map),
);

final _todoIdSchema = SchemanticType.from<Map<String, dynamic>>(
  jsonSchema: {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': 'Todo id, for example todo-1.',
        'minLength': 1,
      },
    },
    'required': ['id'],
  },
  parse: (json) => Map<String, dynamic>.from(json as Map),
);

final _todoRenameSchema = SchemanticType.from<Map<String, dynamic>>(
  jsonSchema: {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': 'Todo id, for example todo-1.',
        'minLength': 1,
      },
      'name': {
        'type': 'string',
        'description': 'New todo name.',
        'minLength': 1,
      },
    },
    'required': ['id', 'name'],
  },
  parse: (json) => Map<String, dynamic>.from(json as Map),
);

final class _TodoPanel extends StatelessWidget {
  const _TodoPanel({required this.todos});

  final List<_TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Todos', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (todos.isEmpty)
            const Text('No todos')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final todo in todos)
                  Chip(
                    avatar: Icon(
                      todo.done ? Icons.check_circle : Icons.circle_outlined,
                      size: 18,
                    ),
                    label: Text('${todo.id}: ${todo.name}'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

final class _TodoItem {
  _TodoItem({required this.id, required this.name});

  final String id;
  String name;
  bool done = false;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'done': done};
}

final class _ToolScopePanel extends StatelessWidget {
  const _ToolScopePanel({
    required this.useAllTools,
    required this.toolNames,
    required this.selectedToolNames,
    required this.manualToolNames,
    required this.onUseAllToolsChanged,
    required this.onManualToolToggled,
  });

  final bool useAllTools;
  final List<String> toolNames;
  final Set<String> selectedToolNames;
  final Set<String> manualToolNames;
  final ValueChanged<bool> onUseAllToolsChanged;
  final void Function(String toolName, bool selected) onManualToolToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Tool scope', style: theme.textTheme.titleSmall),
              const Spacer(),
              FilterChip(
                label: const Text('All tools'),
                selected: useAllTools,
                onSelected: onUseAllToolsChanged,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            useAllTools
                ? 'All tools are passed to Genkit. The model decides what to call.'
                : 'Manual selection: these exact tools are passed to Genkit.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final toolName in toolNames)
                FilterChip(
                  label: Text(toolName),
                  selected: selectedToolNames.contains(toolName),
                  onSelected: useAllTools
                      ? null
                      : (selected) => onManualToolToggled(toolName, selected),
                ),
            ],
          ),
        ],
      ),
    );
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
      _ChatItemType.debug => colorScheme.surfaceContainerLow,
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
              Text(item.label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              if (item.type == _ChatItemType.thinking)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Flexible(child: Text(item.text)),
                  ],
                )
              else
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
  factory _ChatItem.debug(String text) => _ChatItem(_ChatItemType.debug, text);

  final _ChatItemType type;
  String text;

  String get label {
    return switch (type) {
      _ChatItemType.user => 'You',
      _ChatItemType.assistant => 'Assistant',
      _ChatItemType.tool => 'Tool call',
      _ChatItemType.thinking => 'Thinking',
      _ChatItemType.error => 'Error',
      _ChatItemType.debug => 'Debug',
    };
  }
}

enum _ChatItemType { user, assistant, tool, thinking, error, debug }
