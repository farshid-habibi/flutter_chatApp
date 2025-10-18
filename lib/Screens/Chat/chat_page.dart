import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:flutter_chat_bubble/bubble_type.dart';
import 'package:flutter_chat_bubble/clippers/chat_bubble_clipper_1.dart';

class ChatPage extends StatefulWidget {
  final String roomId;
  const ChatPage({super.key, required this.roomId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  Stream<List<Map<String, dynamic>>>? _messageStream;
  String _currentUserId = '';
  bool _isUploading = false;
  String? _chatUserName;
  late RealtimeChannel _channel;

  // Animation controllers برای هر پیام
  final Map<String, AnimationController> _animationControllers = {};

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

    _channel = _supabase.channel('room_${widget.roomId}_realtime');

    _channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: widget.roomId,
      ),
      callback: (payload) {
        setState(() {
          _messageStream = _supabase
              .from('messages')
              .stream(primaryKey: ['id'])
              .eq('room_id', widget.roomId)
              .order('created_at', ascending: true)
              .map((data) => data.cast<Map<String, dynamic>>());
        });
      },
    );

    _channel.subscribe();
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _markMessagesAsRead();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _channel.unsubscribe();
    for (final controller in _animationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final unreadMessages = await _supabase
          .from('messages')
          .select('id')
          .eq('room_id', widget.roomId)
          .neq('sender_id', _currentUserId);

      for (final msg in unreadMessages) {
        await _supabase.from('message_reads').upsert({
          'message_id': msg['id'],
          'user_id': _currentUserId,
        });
      }
    } catch (e) {
      print("❌ Error marking messages as read: $e");
    }
  }

  Future<void> _loadUserName() async {
    try {
      final data = await _supabase
          .from('users')
          .select('username')
          .eq('id', widget.roomId)
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot join chat room')));
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
        'is_video': false,
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
    }

    _controller.clear();
    _scrollToBottom();
  }

  Future<void> _sendMedia() async {
    try {
      final XFile? pickedFile = await _picker.pickMedia();
      if (pickedFile == null) return;

      setState(() => _isUploading = true);

      final File file = File(pickedFile.path);
      final fileExt = pickedFile.path.split('.').last;
      final isVideo = [
        'mp4',
        'mov',
        'avi',
        'mkv',
      ].contains(fileExt.toLowerCase());

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_currentUserId}.$fileExt';

      await _supabase.storage.from('chat_media').upload(fileName, file);

      final mediaUrl = _supabase.storage
          .from('chat_media')
          .getPublicUrl(fileName);

      await _ensureMember();
      await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_id': _currentUserId,
        'content': '',
        'media_url': mediaUrl,
        'is_video': isVideo,
      });

      _scrollToBottom();
    } catch (e, st) {
      print("❌ Error sending media: $e");
      print("📍 $st");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send media')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _saveToDownloads(String url, String fileName) async {
    try {
      final response = await http.get(Uri.parse(url));
      final bytes = response.bodyBytes;
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/$fileName");
      await file.writeAsBytes(bytes);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Saved to device folder")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to save")));
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

  Future<void> _showMessageMenu(
    Offset position,
    Map<String, dynamic> msg,
    bool isMine,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        MediaQuery.of(context).size.width - position.dx,
        0,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('کپی'),
            ],
          ),
        ),
        if (isMine)
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('حذف', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
      ],
    );

    if (selected == 'copy') {
      Clipboard.setData(ClipboardData(text: msg['content'] ?? ''));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('پیام کپی شد')));
    } else if (selected == 'delete') {
      try {
        await _supabase.from('messages').delete().eq('id', msg['id']);
        setState(() {
          _messageStream = _supabase
              .from('messages')
              .stream(primaryKey: ['id'])
              .eq('room_id', widget.roomId)
              .order('created_at', ascending: true)
              .map((data) => data.cast<Map<String, dynamic>>());
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('پیام حذف شد')));
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطا در حذف پیام: $e')));
      }
    }
  }

  Color _getBubbleColor(bool isMine, Map<String, dynamic> msg) {
    if (msg['media_url'] != null && msg['is_video'] == true) {
      return isMine ? Colors.purple.shade400 : Colors.purple.shade100;
    } else if (msg['media_url'] != null) {
      return isMine ? Colors.green.shade100 : Colors.grey.shade300;
    }
    return isMine ? Colors.blue.shade600 : Colors.grey.shade200;
  }

  @override
  Widget build(BuildContext context) {
    if (_messageStream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
                  if (snapshot.hasError)
                    // ignore: curly_braces_in_flow_control_structures
                    return Center(child: Text('Error: ${snapshot.error}'));
                  if (!snapshot.hasData)
                    // ignore: curly_braces_in_flow_control_structures
                    return const Center(child: CircularProgressIndicator());

                  final messages = snapshot.data!;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToBottom(),
                  );

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMine = msg['sender_id'] == _currentUserId;

                      final animationController =
                          _animationControllers[msg['id']] ??
                                AnimationController(
                                  vsync: this,
                                  duration: const Duration(milliseconds: 400),
                                )
                            ..forward();
                      _animationControllers[msg['id']] = animationController;

                      return FadeTransition(
                        opacity: animationController.drive(
                          Tween(begin: 0.0, end: 1.0),
                        ),
                        child: SlideTransition(
                          position: animationController.drive(
                            Tween(
                              begin: const Offset(0, 0.2),
                              end: Offset.zero,
                            ).chain(CurveTween(curve: Curves.easeOut)),
                          ),
                          child: Row(
                            mainAxisAlignment: isMine
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMine)
                                const CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.grey,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onLongPressStart: (details) => _showMessageMenu(
                                  details.globalPosition,
                                  msg,
                                  isMine,
                                ),
                                child: ChatBubble(
                                  clipper: ChatBubbleClipper1(
                                    type: isMine
                                        ? BubbleType.sendBubble
                                        : BubbleType.receiverBubble,
                                  ),
                                  backGroundColor: _getBubbleColor(isMine, msg),
                                  alignment: isMine
                                      ? Alignment.topRight
                                      : Alignment.topLeft,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isMine
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (msg['content'] != null &&
                                          msg['content'].toString().isNotEmpty)
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.7,
                                          ),
                                          child: Text(
                                            msg['content'],
                                            softWrap: true,
                                            textDirection: TextDirection.rtl,
                                            textAlign: TextAlign.justify,
                                            style: TextStyle(
                                              color: isMine
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),

                                      if (msg['media_url'] != null) ...[
                                        const SizedBox(height: 8),
                                        GestureDetector(
                                          onTap: () {
                                            if (msg['is_video'] == true) {
                                              showDialog(
                                                context: context,
                                                builder: (_) => AlertDialog(
                                                  content: SizedBox(
                                                    width: 300,
                                                    height: 200,
                                                    child: Chewie(
                                                      controller: ChewieController(
                                                        videoPlayerController:
                                                            VideoPlayerController.network(
                                                              msg['media_url'],
                                                            ),
                                                        autoPlay: false,
                                                        looping: false,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            } else {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => Scaffold(
                                                    backgroundColor:
                                                        Colors.black,
                                                    body: Stack(
                                                      children: [
                                                        Positioned.fill(
                                                          child: AbsorbPointer(
                                                            absorbing: false,
                                                            child: PhotoView(
                                                              imageProvider:
                                                                  NetworkImage(
                                                                    msg['media_url'],
                                                                  ),
                                                              backgroundDecoration:
                                                                  const BoxDecoration(
                                                                    color: Colors
                                                                        .black,
                                                                  ),
                                                              minScale:
                                                                  PhotoViewComputedScale
                                                                      .contained,
                                                              maxScale:
                                                                  PhotoViewComputedScale
                                                                      .covered *
                                                                  3,
                                                            ),
                                                          ),
                                                        ),

                                                        Positioned(
                                                          top: 0,
                                                          left: 0,
                                                          right: 0,
                                                          child: SafeArea(
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        12,
                                                                    vertical: 8,
                                                                  ),
                                                              color: Colors
                                                                  .black
                                                                  .withOpacity(
                                                                    0.4,
                                                                  ),
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .spaceBetween,
                                                                children: [
                                                                  IconButton(
                                                                    icon: const Icon(
                                                                      Icons
                                                                          .arrow_back,
                                                                      color: Colors
                                                                          .white,
                                                                      size: 26,
                                                                    ),
                                                                    onPressed: () =>
                                                                        Navigator.pop(
                                                                          context,
                                                                        ),
                                                                  ),

                                                                  IconButton(
                                                                    icon: const Icon(
                                                                      Icons
                                                                          .download,
                                                                      color: Colors
                                                                          .white,
                                                                      size: 26,
                                                                    ),
                                                                    onPressed: () =>
                                                                        _saveToDownloads(
                                                                          msg['media_url'],
                                                                          "image_${DateTime.now().millisecondsSinceEpoch}.png",
                                                                        ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: msg['media_url'],
                                              width: 200,
                                              height: 200,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  Container(
                                                    width: 200,
                                                    height: 200,
                                                    color: Colors.grey.shade200,
                                                  ),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      Container(
                                                        width: 200,
                                                        height: 200,
                                                        color: Colors.grey,
                                                        child: const Icon(
                                                          Icons.error,
                                                        ),
                                                      ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        msg['created_at']?.toString().substring(
                                              11,
                                              16,
                                            ) ??
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
                              const SizedBox(width: 6),
                              if (isMine)
                                const CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.blueAccent,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
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
                            horizontal: 14,
                            vertical: 10,
                          ),
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
      ),
    );
  }
}
