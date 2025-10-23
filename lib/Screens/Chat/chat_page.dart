import 'dart:io';
import 'package:bubble/bubble.dart';
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
  final Map<String, Future<VideoPlayerController>> _videoControllers = {};

  Stream<List<Map<String, dynamic>>>? _messageStream;
  String _currentUserId = '';
  bool _isUploading = false;
  String? _chatUserName;
  late RealtimeChannel _channel;
  File? _uploadingMediaFile;

  final Map<String, AnimationController> _animationControllers = {};

  Future<VideoPlayerController> _getVideoController(String url) {
    if (_videoControllers.containsKey(url)) {
      return _videoControllers[url]!;
    }

    final controller = VideoPlayerController.network(url);
    final future = controller.initialize().then((_) {
      controller.setLooping(false);
      controller.pause();
      return controller;
    });

    _videoControllers[url] = future;
    return future;
  }

  void _openMediaFullScreen(String url, bool isVideo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: isVideo
                      ? Chewie(
                          controller: ChewieController(
                            videoPlayerController:
                                VideoPlayerController.network(url),
                            autoPlay: true,
                            looping: false,
                          ),
                        )
                      : PhotoView(
                          imageProvider: NetworkImage(url),
                          backgroundDecoration: const BoxDecoration(
                            color: Colors.black,
                          ),
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 3,
                        ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(
                      Icons.download,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () async {
                      await _saveToDownloads(url, url.split('/').last);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaMessage(
    BuildContext context,
    Map<String, dynamic> msg,
    bool isMine,
  ) {
    final caption = msg['content'] ?? '';
    final int minPreviewLength = 150;
    final bool hasLongText = caption.length > minPreviewLength;
    final ValueNotifier<bool> expanded = ValueNotifier(false);

    final double maxCardWidth = MediaQuery.of(context).size.width * 0.65;

    return ValueListenableBuilder<bool>(
      valueListenable: expanded,
      builder: (context, isExpanded, _) {
        final String displayText = hasLongText && !isExpanded
            ? '${caption.substring(0, minPreviewLength)}...'
            : caption;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: maxCardWidth,
            child: Card(
              color: isMine
                  ? Colors.grey.shade800
                  : Color.fromARGB(255, 131, 48, 129),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _openMediaFullScreen(
                      msg['media_url'],
                      msg['is_video'] == true,
                    ),

                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: msg['is_video'] == true
                          ? FutureBuilder<VideoPlayerController>(
                              future: _getVideoController(msg['media_url']),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return Container(
                                    width: maxCardWidth,
                                    height: 400,
                                    color: Colors.black26,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  );
                                }

                                final controller = snapshot.data!;
                                final aspectRatio =
                                    controller.value.aspectRatio == 0
                                    ? 16 / 9
                                    : controller.value.aspectRatio;

                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: aspectRatio,
                                        child: VideoPlayer(controller),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.play_circle_fill,
                                      color: Colors.white,
                                      size: 64,
                                    ),
                                  ],
                                );
                              },
                            )
                          : CachedNetworkImage(
                              imageUrl: msg['media_url'],
                              width: maxCardWidth,
                              height: 400,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),

                  // متن زیر عکس
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              displayText,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.justify,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (hasLongText)
                            GestureDetector(
                              onTap: () => expanded.value = !expanded.value,
                              child: Text(
                                isExpanded ? 'کم کردن متن' : 'ادامه',
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            msg['created_at']?.toString().substring(11, 16) ??
                                '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

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
    for (final future in _videoControllers.values) {
      future.then((controller) => controller.dispose());
    }
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

  Future<void> _showAddCaptionDialog(File mediaFile, bool isVideo) async {
    final TextEditingController captionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.grey.shade800,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: isVideo
                      ? Container(
                          width: double.infinity,
                          height: 400,
                          color: Colors.black,
                          child: Center(
                            child: Icon(
                              Icons.videocam,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                        )
                      : Image.file(
                          mediaFile,
                          width: double.infinity,
                          height: 400,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: captionController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "نوشتن متن...",
                    hintStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.grey.shade800,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "لغو",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, captionController.text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text("ارسال"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).then((captionText) {
      if (captionText != null && captionText.isNotEmpty) {
        // اینجا متن را همراه عکس/ویدیو آپلود کن
        _uploadMediaWithCaption(mediaFile, isVideo, captionText);
      }
    });
  }

  Future<void> _uploadMediaWithCaption(
    File file,
    bool isVideo,
    String? caption,
  ) async {
    setState(() {
      _isUploading = true;
      _uploadingMediaFile = file;
    });

    try {
      final fileExt = file.path.split('.').last;
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
        'content': caption ?? '',
        'media_url': mediaUrl,
        'is_video': isVideo,
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to upload media')));
    } finally {
      setState(() {
        _isUploading = false;
        _uploadingMediaFile = null;
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

      final captionController = TextEditingController();
      final caption = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('افزودن توضیح'),
          content: TextField(
            controller: captionController,
            decoration: const InputDecoration(
              hintText: 'توضیحی برای عکس یا ویدیو بنویس...',
            ),
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, captionController.text.trim()),
              child: const Text('ارسال'),
            ),
          ],
        ),
      );

      if (caption == null) return;

      final File file = File(pickedFile.path);
      final fileExt = pickedFile.path.split('.').last.toLowerCase();
      final isVideo = ['mp4', 'mov', 'avi', 'mkv'].contains(fileExt);

      setState(() {
        _isUploading = true;
        _uploadingMediaFile = file;
      });

      final int fileSize = await file.length();
      const int limitBytes = 10 * 1024 * 1024; // 6MB
      if (fileSize > limitBytes) {}

      await _uploadMediaWithCaption(file, isVideo, caption);
      _scrollToBottom();
    } catch (e, st) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('خطا در ارسال فایل')));
    } finally {
      setState(() {
        _isUploading = false;
        _uploadingMediaFile = null;
      });
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
    if (msg['media_url'] != null) {
      return Colors.transparent;
    }
    return isMine
        ? Colors.grey.shade800
        : const Color.fromARGB(255, 131, 48, 129); // سرمه‌ای
  }

  @override
  Widget build(BuildContext context) {
    if (_messageStream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/images/background.png"),
          fit: BoxFit.cover,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            _chatUserName ?? 'Loading...',
            style: const TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),

        body: Column(
          children: [
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
                    key: PageStorageKey('chat_list_${widget.roomId}'),
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
                          child: GestureDetector(
                            onLongPressStart: (details) => _showMessageMenu(
                              details.globalPosition,
                              msg,
                              isMine,
                            ),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              alignment: isMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: msg['media_url'] != null
                                  ? _buildMediaMessage(context, msg, isMine)
                                  : Bubble(
                                      nip: isMine
                                          ? BubbleNip.rightTop
                                          : BubbleNip.leftTop,
                                      color: _getBubbleColor(isMine, msg),
                                      elevation: 1,
                                      child: Column(
                                        crossAxisAlignment: isMine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.7,
                                            ),
                                            child: Text(
                                              msg['content'] ?? '',
                                              softWrap: true,
                                              textDirection: TextDirection.rtl,
                                              textAlign: TextAlign.justify,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
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
                                              fontSize: 12,
                                              color: isMine
                                                  ? Colors.white70
                                                  : Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.attach_file,
                          color: Colors.black54,
                        ),
                        onPressed: _sendMedia,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // TextField
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: "Write a message...",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // دکمه ارسال پیام
                    Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF128C7E), // رنگ سبز WhatsApp
                      ),
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
