// lib/live_chat_view.dart
//
// Sleek, modern chat view with gradient background, glassmorphism,
// connection status pill, and streaming output from LiveService.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'live_service.dart';

class LiveChatApp extends StatelessWidget {
  const LiveChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Live Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
        fontFamily: 'SF Pro Display',
      ),
      home: const LiveChatView(),
    );
  }
}

class LiveChatView extends StatefulWidget {
  const LiveChatView({super.key});

  @override
  State<LiveChatView> createState() => _LiveChatViewState();
}

class _LiveChatViewState extends State<LiveChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final LiveService _service;
  final List<_Msg> _messages = [];
  String _streaming = '';
  String _status = 'idle';

  @override
  void initState() {
    super.initState();
    try {
      _service = LiveService();
      _service.statusStream.listen((s) {
        setState(() => _status = s);
      });
      _service.incomingText.listen((chunk) {
        setState(() {
          _streaming += chunk;
        });
        _scrollToEnd();
      });
      // Eagerly connect so the first message is snappy
      _service.connect();
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _snack('Config error: $e');
      });
    }
  }

  @override
  void dispose() {
    _service.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_Msg('You', text));
      _input.clear();
      _streaming = '';
    });

    try {
      await _service.sendText(text);
      // Once the server marks turnComplete, we snapshot the stream into the list
      // We also listen for the '\n' we inject in LiveService to signal end-of-turn,
      // but to keep UI simple we finalize on a short delay.
      await Future.delayed(const Duration(milliseconds: 250));
      setState(() {
        if (_streaming.trim().isNotEmpty) {
          _messages.add(_Msg('Bot', _streaming.trim()));
        }
        _streaming = '';
      });
      _scrollToEnd();
    } catch (e) {
      setState(() {
        _messages.add(_Msg('Bot', 'Error: $e'));
        _streaming = '';
      });
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final model =
        dotenv.env['GEMINI_LIVE_MODEL_ID'] ?? 'gemini-2.0-flash-live-001';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0f172a), Color(0xFF111827), Color(0xFF1f2937)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _AppBar(status: _status, model: model),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount:
                            _messages.length + (_streaming.isNotEmpty ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _messages.length && _streaming.isNotEmpty) {
                            return _StreamingBubble(text: _streaming);
                          }
                          final m = _messages[i];
                          final isUser = m.role == 'You';
                          return _Bubble(
                            role: m.role,
                            text: m.text,
                            isUser: isUser,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              _InputBar(
                controller: _input,
                onSend: _send,
                busy: _status == 'connecting',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Msg {
  final String role;
  final String text;
  const _Msg(this.role, this.text);
}

class _AppBar extends StatelessWidget {
  final String status;
  final String model;
  const _AppBar({required this.status, required this.model});

  Color get _dot {
    switch (status) {
      case 'ready':
      case 'connected':
        return const Color(0xFF22c55e);
      case 'connecting':
        return const Color(0xFFf59e0b);
      case 'error':
      case 'closed':
      case 'disconnected':
        return const Color(0xFFef4444);
      default:
        return const Color(0xFF9ca3af);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.psychology_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gemini Live',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'status: $status · $model',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String role;
  final String text;
  final bool isUser;
  const _Bubble({required this.role, required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final gradient = isUser
        ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])
        : null;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          gradient: gradient,
          color: isUser ? null : Colors.white.withOpacity(0.08),
          border: isUser
              ? null
              : Border.all(color: Colors.white.withOpacity(0.15)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 8),
            bottomRight: Radius.circular(isUser ? 8 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          '${role == 'You' ? '' : '🤖 '}$text',
          style: TextStyle(
            color: Colors.white,
            height: 1.5,
            fontWeight: isUser ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  final String text;
  const _StreamingBubble({required this.text});
  @override
  Widget build(BuildContext context) {
    return _Bubble(role: 'Bot', text: text, isUser: false);
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool busy;
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Type your message…',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: busy ? null : onSend,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
