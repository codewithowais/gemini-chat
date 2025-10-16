// lib/gemini_service.dart
// 
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  // ---- immutable env/config ----
  final String _apiKey;
  String _modelId;
  final GenerationConfig _config;
  final List<SafetySetting> _safety;

  // ---- SDK objects ----
  late GenerativeModel _model;
  late ChatSession _chat;

  // Use this getter if your UI wants to show which model is active
  String get modelId => _modelId;

  GeminiService._({
    required String apiKey,
    required String modelId,
    required GenerationConfig config,
    required List<SafetySetting> safety,
  }) : _apiKey = apiKey,
       _modelId = modelId,
       _config = config,
       _safety = safety {
    _model = GenerativeModel(
      model: _modelId,
      apiKey: _apiKey,
      generationConfig: _config,
      safetySettings: _safety,
    );
    _chat = _model.startChat(
      history: [
        Content.text(
          'You are a helpful assistant. Keep answers concise unless asked otherwise.',
        ),
      ],
    );
  }

  /// Factory that reads .env and builds the service.
  factory GeminiService() {
    final key = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (key.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY in .env');
    }

    final id = (dotenv.env['GEMINI_MODEL_ID'] ?? '').trim().isNotEmpty
        ? dotenv.env['GEMINI_MODEL_ID']!.trim()
        : 'gemini-flash-latest'; // you can pin: 'gemini-1.5-flash-002' etc.

    // Tunable decoding parameters.
    final genConfig = GenerationConfig(
      temperature: 0.7,
      topK: 40,
      topP: 0.95,
      maxOutputTokens: 1024,
    );

    // Safety settings are optional; adjust as needed. :contentReference[oaicite:2]{index=2}
    final safety = <SafetySetting>[
      SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.low),
      SafetySetting(HarmCategory.harassment, HarmBlockThreshold.low),
      SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.low),
      SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.low),
    ];

    return GeminiService._(
      apiKey: key,
      modelId: id,
      config: genConfig,
      safety: safety,
    );
  }

  /// Start a new chat session (clears history).
  void resetChat({List<Content>? preamble}) {
    _chat = _model.startChat(
      history:
          preamble ??
          [
            Content.text(
              'You are a helpful assistant. Keep answers concise unless asked otherwise.',
            ),
          ],
    );
  }

  /// Non-streaming chat.
  Future<String> sendMessage(String message) async {
    try {
      final resp = await _chat.sendMessage(Content.text(message));
      final t = resp.text?.trim();
      return (t == null || t.isEmpty) ? '(no response)' : t;
    } catch (e, st) {
      debugPrint('sendMessage error: $e\n$st');
      return 'Error: $e';
    }
  }

  /// Streaming chat.
  Stream<String> sendMessageStream(String message) async* {
    try {
      final stream = _chat.sendMessageStream(Content.text(message));
      await for (final chunk in stream) {
        final t = chunk.text;
        if (t != null && t.isNotEmpty) yield t;
      }
    } catch (e, st) {
      debugPrint('sendMessageStream error: $e\n$st');
      yield 'Error: $e';
    }
  }

  /// Multimodal (text + images) single-turn helper.
  Future<String> sendMultimodal(
    List<String> textParts,
    List<Uint8List> imagesBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final parts = <Part>[
        for (final s in textParts) TextPart(s),
        for (final img in imagesBytes) DataPart(mimeType, img),
      ];
      final resp = await _model.generateContent([Content.multi(parts)]);
      final t = resp.text?.trim();
      return (t == null || t.isEmpty) ? '(no response)' : t;
    } catch (e, st) {
      debugPrint('sendMultimodal error: $e\n$st');
      return 'Error: $e';
    }
  }

  /// Switch models at runtime using stored config/safety.
  Future<void> switchModel(String newModelId) async {
    _modelId = newModelId;
    _model = GenerativeModel(
      model: _modelId,
      apiKey: _apiKey,
      generationConfig: _config,
      safetySettings: _safety,
    );
    resetChat();
  }

  /// List models your key can access (SDK has no listModels). :contentReference[oaicite:3]{index=3}
  Future<List<String>> listModels() async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models?key=$_apiKey',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('List models failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final models =
        (data['models'] as List<dynamic>? ?? [])
            .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
          ..sort();
    return models;
  }
}
