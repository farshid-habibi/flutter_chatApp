import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  final String roomId; // شناسه اتاق
  const ChatPage({super.key, required this.roomId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _supabase = Supabase.instance.client;
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _listenMessages();
  }

  void _listenMessages() {
    _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('created_at')
        .listen((event) {
      setState(() {
        _messages = event;
      });

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      print('Error: User not logged in');
      return;
    }

    // لاگ قبل از Insert
    print('Sending message...');
    print('User ID: $userId');
    print('Room ID: ${widget.roomId}');
    print('Content: $text');

    try {
      final res = await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'user_id': userId,
        'content': text,
      });

      print('Insert result: $res');

      // اضافه کردن فوری پیام به لیست برای نمایش لحظه‌ای
      setState(() {
        _messages.add({
          'room_id': widget.roomId,
          'user_id': userId,
          'content': text,
          'created_at': DateTime.now().toIso8601String(),
        });
      });

      _controller.clear();

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _supabase.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("اتاق چت"),
        actions: [
          IconButton(
            onPressed: () => _supabase.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final mine = msg['user_id'] == currentUser;

                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: mine ? Colors.blueAccent : Colors.grey.shade300,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: mine ? const Radius.circular(14) : const Radius.circular(0),
                        bottomRight: mine ? const Radius.circular(0) : const Radius.circular(14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['content'] ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            color: mine ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['created_at'].toString().substring(11, 16),
                          style: TextStyle(
                            fontSize: 11,
                            color: mine ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: "پیام خود را بنویسید...",
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
