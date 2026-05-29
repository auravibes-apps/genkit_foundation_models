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
  final _promptController = TextEditingController(
    text: 'Write a two sentence welcome message for a Genkit plugin.',
  );
  final _nativeApi = PigeonFoundationModelsApi();
  late final Genkit _genkit;

  bool? _isAvailable;
  var _isGenerating = false;
  String? _responseText;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _genkit = Genkit(
      isDevEnv: false,
      plugins: [FoundationModelsPlugin()],
      model: modelRef(FoundationModelsPlugin.defaultModelName),
    );
    unawaited(_checkAvailability());
  }

  @override
  void dispose() {
    _promptController.dispose();
    unawaited(_genkit.shutdown());
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    try {
      final isAvailable = await _nativeApi.isAvailable();
      if (!mounted) return;
      setState(() {
        _isAvailable = isAvailable;
        _errorText = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isAvailable = false;
        _errorText = _errorMessage(error);
      });
    }
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _responseText = null;
      _errorText = null;
    });

    try {
      final response = await _genkit.generate(
        prompt: prompt,
        config: {'temperature': 0.2, 'maxOutputTokens': 256},
      );
      if (!mounted) return;
      setState(() {
        _responseText = response.text;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = _errorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
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
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Apple Foundation Models: $availability'),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Prompt',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isGenerating ? null : _generate,
            child: Text(_isGenerating ? 'Generating...' : 'Generate'),
          ),
          const SizedBox(height: 24),
          if (_responseText case final responseText?) ...[
            Text('Response', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(responseText),
          ],
          if (_errorText case final errorText?) ...[
            Text('Error', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(errorText),
          ],
        ],
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is FoundationModelsException) return error.userMessage;
    return error.toString();
  }
}
