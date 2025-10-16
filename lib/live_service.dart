// lib/live_service.dart
//
// Minimal Live API (WebSocket) text chat for Flutter.
// Reads API key & model id from .env (do NOT hardcode).
//
// Required pubspec deps:
//   web_socket_channel: ^2.4.5
//   flutter_dotenv: ^5.1.0
//
// .env keys used:
//   GEMINI_API_KEY=your_key
//   GEMINI_LIVE_MODEL_ID=gemini-2.0-flash-live-001
//
// Notes:
// - Auth: pass ?key=... on the WebSocket URL and also send x-goog-api-key header.
// - First message MUST be "setup" (model + generationConfig).
// - For simple text chat, we send `clientContent` with a text turn and `turnComplete: true`.
// - We parse server messages and emit text chunks as they arrive.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

class LiveService {
  static const _wsPath =
      'ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  final _incomingTextCtrl = StreamController<String>.broadcast();
  final _statusCtrl = StreamController<String>.broadcast();

  WebSocketChannel? _channel;
  bool _isSetupComplete = false;
  bool _connecting = false;

  String get modelId =>
      (dotenv.env['GEMINI_LIVE_MODEL_ID']?.trim().isNotEmpty ?? false)
      ? dotenv.env['GEMINI_LIVE_MODEL_ID']!.trim()
      : 'gemini-2.0-flash-live-001'; // You may swap to gemini-live-2.5-flash(-preview)

  String get apiKey {
    final k = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (k.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY in .env');
    }
    return k;
  }

  Stream<String> get incomingText => _incomingTextCtrl.stream;
  Stream<String> get statusStream => _statusCtrl.stream;

  Future<void> connect() async {
    if (_channel != null || _connecting) return;
    _connecting = true;
    _status('connecting');

    final url = Uri.parse(
      'wss://generativelanguage.googleapis.com/$_wsPath?key=$apiKey',
    );

    try {
      // Add both header and query param to be safe.
      final headers = {'x-goog-api-key': apiKey};

      // Some platforms require explicit WebSocket.connect for headers:
      final socket = await WebSocket.connect(url.toString(), headers: headers);
      _channel = WebSocketChannel(socket);

      _status('connected');
      _listen();

      // Send initial setup
      await _sendSetup();
    } catch (e, st) {
      _status('error: $e');
      debugPrint('LiveService.connect error: $e\n$st');
      _connecting = false;
      rethrow;
    }
    _connecting = false;
  }

  Future<void> disconnect() async {
    try {
      await _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
    _isSetupComplete = false;
    _status('disconnected');
  }

  Future<void> _sendSetup() async {
    final setupMessage = {
      "setup": {
        "generationConfig": {
          "temperature": 0.7,
          "topK": 40,
          "topP": 0.95,
          "maxOutputTokens": 1024,
          "responseModalities": ["TEXT"], // we want text back
        },
        "systemInstruction":
            "You are a helpful, concise assistant. Keep responses tight unless asked.",
        "model": modelId,
      },
    };

    _sendJson(setupMessage);
  }

  /// Send a user text prompt. This uses clientContent (not realtimeInput) for simplicity.
  Future<void> sendText(String text) async {
    if (_channel == null) {
      await connect();
    }
    if (!_isSetupComplete) {
      // It’s safe to queue after setup is confirmed, but for simplicity we just wait a bit
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final message = {
      "clientContent": {
        "turns": [
          {
            "role": "user",
            "parts": [
              {"text": text},
            ],
          },
        ],
        "turnComplete": true,
      },
    };

    _sendJson(message);
  }

  void _listen() {
    _channel!.stream.listen(
      (event) {
        try {
          final msg = jsonDecode(event as String) as Map<String, dynamic>;

          // 1) Setup complete?
          if (msg.containsKey('setupComplete')) {
            _isSetupComplete = true;
            _status('ready'); // connected + setup ok
            return;
          }

          // 2) Server content (incremental model updates)
          if (msg.containsKey('serverContent')) {
            final sc = msg['serverContent'] as Map<String, dynamic>;
            // modelTurn is a Content object. We extract text parts if any.
            if (sc.containsKey('modelTurn')) {
              final modelTurn = sc['modelTurn'] as Map<String, dynamic>;
              final parts = modelTurn['parts'] as List<dynamic>?;

              if (parts != null && parts.isNotEmpty) {
                for (final p in parts) {
                  final map = (p as Map<String, dynamic>);
                  final text = map['text'];
                  if (text is String && text.isNotEmpty) {
                    _incomingTextCtrl.add(text);
                  }
                }
              }
            }

            // Optional: a flag that generation finished
            final done =
                (sc['generationComplete'] == true) ||
                (sc['turnComplete'] == true);
            if (done) {
              _incomingTextCtrl.add('\n'); // add a newline when a turn ends
            }
            return;
          }

          // 3) Transcriptions (if using audio) — ignored here
          // 4) Tool calls — ignored here

          // Unknown message types are ignored
        } catch (e) {
          debugPrint('LiveService listen parse error: $e');
        }
      },
      onDone: () {
        _status('closed');
        _channel = null;
        _isSetupComplete = false;
      },
      onError: (e) {
        _status('error: $e');
        _channel = null;
        _isSetupComplete = false;
      },
    );
  }

  void _sendJson(Map<String, dynamic> obj) {
    if (_channel == null) return;
    final s = jsonEncode(obj);
    _channel!.sink.add(s);
  }

  void _status(String s) {
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  void dispose() {
    _incomingTextCtrl.close();
    _statusCtrl.close();
    disconnect();
  }
}
