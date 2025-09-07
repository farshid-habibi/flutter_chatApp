import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class ChatPage extends StatefulWidget {
  final String roomId; // اینجا roomId رو همون userId فرض کردم
  const ChatPage({super.key, required this.roomId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  late final Stream<List<Map<String, dynamic>>> _messageStream;
  String _currentUserId = '';
  bool _isUploading = false;
  String? _chatUserName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = _supabase.auth.currentUser?.id ?? '';
    _loadUserName();

    _messageStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('created_at', ascending: true)
        .map((data) => data.cast<Map<String, dynamic>>());
  }

  Future<void> _loadUserName() async {
    try {
      final data = await _supabase
          .from('users') // 👈 جدول کاربرانت
          .select('username')
          .eq('id', widget.roomId) // 👈 فرض کردم roomId = userId
          .maybeSingle();

      setState(() {
        _chatUserName = data?['username'] ?? 'Chat Room';
      });
    } catch (e) {
      setState(() {
        _chatUserName = 'Chat Room';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureMember() async {
    try {
      final memberCheck = await _supabase
          .from('room_members')
          .select()
          .eq('room_id', widget.roomId)
          .eq('user_id', _currentUserId)
          .limit(1);

      if (memberCheck.isEmpty) {
        await _supabase.from('room_members').insert({
          'room_id': widget.roomId,
          'user_id': _currentUserId,
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot join chat room')),
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _currentUserId.isEmpty) return;

    try {
      await _ensureMember();
      await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_id': _currentUserId,
        'content': text,
        'media_url': null,
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message')),
      );
    }

    _controller.clear();
    _scrollToBottom();
  }

  Future<void> _sendMedia() async {
    try {
      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      setState(() => _isUploading = true);

      final File file = File(pickedFile.path);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_currentUserId}.jpg';

      await _supabase.storage.from('chat_media').upload(fileName, file);

      final mediaUrl =
          _supabase.storage.from('chat_media').getPublicUrl(fileName);

      await _ensureMember();
      await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_id': _currentUserId,
        'content': '',
        'media_url': mediaUrl,
      });

      _scrollToBottom();
    } catch (e, st) {
      print("❌ Error sending media: $e");
      print("📍 $st");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send media')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_chatUserName ?? 'Loading...')),
      body: Column(
        children: [
          if (_isUploading)
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text("Uploading media...", style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messageStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMine = msg['sender_id'] == _currentUserId;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: isMine
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: [
                        if (!isMine)
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.grey.shade400,
                            child: const Icon(Icons.person,
                                size: 16, color: Colors.white),
                          ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isMine
                                  ? Colors.blueAccent
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: isMine
                                    ? const Radius.circular(16)
                                    : const Radius.circular(0),
                                bottomRight: isMine
                                    ? const Radius.circular(0)
                                    : const Radius.circular(16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: isMine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (msg['content'] != null &&
                                    msg['content'].toString().isNotEmpty)
                                  Text(
                                    msg['content'],
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: isMine
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                if (msg['media_url'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedNetworkImage(
                                        imageUrl: msg['media_url'],
                                        width: 220,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Container(
                                                height: 150,
                                                child: const Center(
                                                    child:
                                                        CircularProgressIndicator())),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                          height: 150,
                                          color: Colors.grey,
                                          child: const Icon(Icons.error),
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  msg['created_at']
                                          ?.toString()
                                          .substring(11, 16) ??
                                      '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isMine
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isMine) const SizedBox(width: 6),
                        if (isMine)
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.blueAccent,
                            child: const Icon(Icons.person,
                                size: 16, color: Colors.white),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _sendMedia,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: "Write a message...",
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
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
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
