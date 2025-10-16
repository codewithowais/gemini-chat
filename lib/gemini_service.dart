// lib/gemini_service.dart
// Complete Gemini service for Flutter using google_generative_ai.
// - .env driven (GEMINI_API_KEY, GEMINI_MODEL_ID)
// - startChat() multi-turn
// - sendMessage() (non-stream) and sendMessageStream() (streaming)
// - listModels() via REST (SDK doesn't expose it)
// - simple SafetySettings (optional) and GenerationConfig

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  /// Expose the current model id (from .env or default)
  final String modelId;

  late final GenerativeModel _model;
  late ChatSession _chat;

  GeminiService._(this.modelId, this._model, this._chat);

  /// Factory that reads .env and builds a ready-to-use chat session.
  factory GeminiService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY in .env');
    }

    // Prefer a rolling alias that stays valid across catalogs.
    final id = (dotenv.env['GEMINI_MODEL_ID'] ?? '').trim().isNotEmpty
        ? dotenv.env['GEMINI_MODEL_ID']!.trim()
        : 'gemini-flash-latest';

    // Optional: tune decoding params here.
    final genConfig = GenerationConfig(
      temperature: 0.7,
      topK: 40,
      topP: 0.95,
      maxOutputTokens: 1024,
    );

    // Optional: loosen/tighten as needed (can be removed if you don’t need it).
    // See docs for available categories/thresholds.
    final safety = <SafetySetting>[
      SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.low),
      SafetySetting(HarmCategory.harassment, HarmBlockThreshold.low),
      SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.low),
      SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.low),
    ];

    final model = GenerativeModel(
      model: id,
      apiKey: apiKey,
      generationConfig: genConfig,
      safetySettings: safety,
    );

    final chat = model.startChat(
      history: [
        Content.text(
          'You are a helpful assistant. Keep answers concise unless asked otherwise.',
        ),
      ],
    );

    return GeminiService._(id, model, chat);
  }

  /// Start a new chat, clearing history.
  void resetChat({List<Content>? systemPreamble}) {
    _chat = _model.startChat(
      history:
          systemPreamble ??
          [
            Content.text(
              'You are a helpful assistant. Keep answers concise unless asked otherwise.',
            ),
          ],
    );
  }

  /// Non-streaming message: returns the full response as a String.
  Future<String> sendMessage(String message) async {
    try {
      final resp = await _chat.sendMessage(Content.text(message));
      return resp.text?.trim().isNotEmpty == true
          ? resp.text!.trim()
          : '(no response)';
    } catch (e, st) {
      debugPrint('Gemini sendMessage error: $e\n$st');
      return 'Error: $e';
    }
  }

  /// Streaming message: yields partial text chunks as they arrive.
  /// Combine them in the UI if you want the full message.
  Stream<String> sendMessageStream(String message) async* {
    try {
      final stream = _chat.sendMessageStream(Content.text(message));
      await for (final chunk in stream) {
        final t = chunk.text;
        if (t != null && t.isNotEmpty) yield t;
      }
    } catch (e, st) {
      debugPrint('Gemini sendMessageStream error: $e\n$st');
      yield 'Error: $e';
    }
  }

  /// Attach text and one or more images (bytes) in a single prompt.
  /// Example usage:
  ///   final bytes = await rootBundle.load('assets/receipt.jpg');
  ///   await sendMultimodal(['What is in this receipt?'], [bytes.buffer.asUint8List()]);
  Future<String> sendMultimodal(
    List<String> textParts,
    List<Uint8List> imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final parts = <Part>[
        for (final s in textParts) TextPart(s),
        for (final img in imageBytes) DataPart(mimeType, img),
      ];
      final resp = await _model.generateContent([Content.multi(parts)]);
      return resp.text?.trim().isNotEmpty == true
          ? resp.text!.trim()
          : '(no response)';
    } catch (e, st) {
      debugPrint('Gemini sendMultimodal error: $e\n$st');
      return 'Error: $e';
    }
  }

  /// List available model IDs for your API key by calling the Models REST API.
  /// NOTE: The Dart SDK does not provide a listModels method; this is the supported way.
  Future<List<String>> listModels() async {
    final key = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (key.isEmpty) throw Exception('Missing GEMINI_API_KEY in .env');

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models?key=$key',
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

  /// Optionally switch models at runtime (e.g., from a dropdown).
  Future<void> switchModel(String newModelId) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) throw Exception('Missing GEMINI_API_KEY in .env');

    _model = GenerativeModel(
      model: newModelId,
      apiKey: apiKey,
      generationConfig: _model.generationConfig,
      safetySettings: _model.safetySettings,
    );
    resetChat(); // resets chat with the new model
  }
}
