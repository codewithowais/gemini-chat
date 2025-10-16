import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'gemini_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gemini Chat',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const ChatView(),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({super.key});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _controller = TextEditingController();
  late final GeminiService _service;
  final List<_Message> _messages = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    try {
      _service = GeminiService();
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnack('Config error: $e');
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _messages.add(_Message(role: 'You', text: text));
      _controller.clear();
      _busy = true;
    });

    final reply = await _service.sendMessage(text);
    setState(() {
      _messages.add(_Message(role: 'Bot', text: reply));
      _busy = false;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isUser = m.role == 'You';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.blue.shade50
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${m.role}: ${m.text}'),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ElevatedButton(
                    onPressed: _busy ? null : _send,
                    child: const Text('Send'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message {
  final String role;
  final String text;
  const _Message({required this.role, required this.text});
}
