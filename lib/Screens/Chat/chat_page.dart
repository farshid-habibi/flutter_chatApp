import 'dart:io';
import 'package:bubble/bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
  Map<String, dynamic>? _replyingTo;
  final Map<String, int> messageIndexes = {};
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  Stream<List<Map<String, dynamic>>>? _messageStream;
  String _currentUserId = '';
  bool _isUploading = false;
  String? _chatUserName;
  late RealtimeChannel _channel;
  File? _uploadingMediaFile;
  final Map<String, GlobalKey> messageKeys = {};
  Map<String, bool> highlightedMessages = {};
  bool _showScrollToBottom = false;

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
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: const Color.fromARGB(255, 85, 220, 155),
                  width: 2,
                ),
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
                        top: Radius.circular(16),
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

                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                            child: Text(
                              displayText,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.justify,
                              style: const TextStyle(
                                fontFamily: 'Vazir',
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (hasLongText)
                            GestureDetector(
                              onTap: () => expanded.value = !expanded.value,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  0,
                                ),
                                child: Text(
                                  isExpanded ? 'کم کردن متن' : 'ادامه',
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                    fontFamily: 'Vazir',
                                    color: Colors.blueAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),

                  //To do
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                    child: Text(
                      msg['created_at']?.toString().substring(11, 16) ?? '',
                      style: const TextStyle(
                        fontFamily: 'Vazir',
                        color: Colors.white70,
                        fontSize: 11,
                      ),
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

    // لیسنر برای دکمه اسکرول به پایین
    _itemPositionsListener.itemPositions.addListener(() {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      final lastVisibleIndex = positions
          .map((e) => e.index)
          .reduce((a, b) => a > b ? a : b);
      final isAtBottom = lastVisibleIndex >= (messageIndexes.length - 3);

      if (_showScrollToBottom != !isAtBottom) {
        setState(() {
          _showScrollToBottom = !isAtBottom;
        });
      }
    });

    _currentUserId = _supabase.auth.currentUser?.id ?? '';
    _loadUserName();

    // فقط یک بار استریم بساز
    _messageStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('created_at', ascending: true)
        .map((data) => data.cast<Map<String, dynamic>>());

    // نیازی به onPostgresChanges نیست
    _channel = _supabase.channel('room_${widget.roomId}_realtime');
    _channel.subscribe();

    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _markMessagesAsRead();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();

    // لغو سابسکرایب کانال
    _channel.unsubscribe();

    // پاک کردن کنترلرهای ویدیو
    for (final future in _videoControllers.values) {
      future.then((controller) => controller.dispose());
    }

    // پاک کردن انیمیشن‌ها
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
                    hintStyle: TextStyle(
                      color: Colors.white54,
                      fontFamily: 'Vazir',
                    ),
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
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontFamily: 'Vazir',
                        ),
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
        if (_replyingTo != null) 'reply_to': _replyingTo!['id'],
      });
      setState(() {
        _replyingTo = null; // بعد از ارسال پاک می‌شود
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
      if (_itemScrollController.isAttached && messageIndexes.isNotEmpty) {
        final lastIndex = messageIndexes.values.isNotEmpty
            ? messageIndexes.values.reduce((a, b) => a > b ? a : b)
            : 0;

        _itemScrollController.scrollTo(
          index: lastIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          alignment: 0.0,
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
          value: 'reply',
          child: Row(
            children: [
              Icon(Icons.replay, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text('reply', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text('Copy', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        if (isMine)
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text('delete', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
      ],
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      color: Colors.black.withOpacity(0.8),
    );

    if (selected == 'copy') {
      Clipboard.setData(ClipboardData(text: msg['content'] ?? ''));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('پیام کپی شد')));
    } else if (selected == 'delete') {
      try {
        await _supabase.from('messages').delete().eq('id', msg['id']);
        // ⚠️ دیگر نیازی به setState روی _messageStream نیست
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('پیام حذف شد')));
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطا در حذف پیام: $e')));
      }
    } else if (selected == 'reply') {
      setState(() {
        _replyingTo = msg;
      });
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

  void _highlightMessage(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final topLeft = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: topLeft.dx,
        top: topLeft.dy,
        width: size.width,
        height: size.height,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent, width: 3),
              // optional: slightly transparent background
              color: Colors.blueAccent.withOpacity(0.06),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    // مدت زمان نمایش هایلایت (قابل تغییر)
    await Future.delayed(const Duration(milliseconds: 700));
    overlayEntry.remove();
  }

  Future<void> scrollToMessage(String messageId) async {
    final index = messageIndexes[messageId];
    if (index == null) return;

    // اسکرول نرم تا پیام
    await _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.3,
    );

    setState(() {
      highlightedMessages[messageId] = true;
    });

    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      highlightedMessages[messageId] = false;
    });
  }

  void highlightMessage(int index) {}

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
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages = snapshot.data!;

                  // ⚡ ثبت پیام‌های جدید فقط
                  for (var i = 0; i < messages.length; i++) {
                    final msg = messages[i];
                    final messageId = msg['id'];

                    if (!messageIndexes.containsKey(messageId)) {
                      messageIndexes[messageId] = i;
                    }

                    messageKeys.putIfAbsent(messageId, () => GlobalKey());

                    // ⚡ AnimationController فقط برای پیام‌های جدید
                    _animationControllers.putIfAbsent(
                      messageId,
                      () => AnimationController(
                        vsync: this,
                        duration: const Duration(milliseconds: 400),
                      )..forward(),
                    );
                  }

                  if (messages.length > messageIndexes.length) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToBottom(),
                    );
                  }

                  return ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    reverse: false,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final messageId = msg['id'];
                      final isMine = msg['sender_id'] == _currentUserId;
                      final animationController =
                          _animationControllers[messageId]!;

                      return FadeTransition(
                        key: ValueKey(messageId), // ⚡ Key ثابت برای هر پیام
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
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: highlightedMessages[msg['id']] == true
                                  ? const EdgeInsets.all(2)
                                  : EdgeInsets.zero,
                              decoration: highlightedMessages[msg['id']] == true
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.lightBlueAccent,
                                        width: 3,
                                      ),
                                      color: Colors.lightBlueAccent.withOpacity(
                                        0.1,
                                      ),
                                    )
                                  : null,
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
                                          // نمایش ریپلای
                                          if (msg['reply_to'] != null)
                                            GestureDetector(
                                              onTap: () async {
                                                await scrollToMessage(
                                                  msg['reply_to'],
                                                );
                                              },
                                              child: Builder(
                                                builder: (context) {
                                                  final replyMsg = messages
                                                      .firstWhere(
                                                        (m) =>
                                                            m['id'] ==
                                                            msg['reply_to'],
                                                        orElse: () => {},
                                                      );
                                                  if (replyMsg.isEmpty) {
                                                    return const SizedBox.shrink();
                                                  }

                                                  final maxCardWidth =
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.width *
                                                      0.65;

                                                  return Container(
                                                    constraints: BoxConstraints(
                                                      maxWidth: maxCardWidth,
                                                    ),
                                                    margin:
                                                        const EdgeInsets.only(
                                                          bottom: 6,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black
                                                          .withOpacity(0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: const Border(
                                                        left: BorderSide(
                                                          color: Colors
                                                              .lightBlueAccent,
                                                          width: 3,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      replyMsg['content'] ??
                                                          '[Media]',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textDirection:
                                                          TextDirection.rtl,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),

                                          // متن اصلی پیام
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

                                          // زمان ارسال
                                          Text(
                                            msg['created_at']
                                                    ?.toString()
                                                    .substring(11, 16) ??
                                                '',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ✅ نمایش نوار ریپلای بالای TextField (در صورت وجود)
                    if (_replyingTo != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 40,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Replying to:',
                                    style: TextStyle(
                                      color: Colors.blueAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _replyingTo!['content'] ?? '[Media]',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                setState(() {
                                  _replyingTo = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                    Row(
                      children: [
                        // 📎 دکمه فایل
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

                        Expanded(
                          child: TextField(
                            controller: _controller,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              hintText: "پیام خود را بنویسید...",
                              hintStyle: const TextStyle(color: Colors.black54),
                              filled: true,
                              fillColor: Colors.white,
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

                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF128C7E), // رنگ سبز واتساپ
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: AnimatedOpacity(
          opacity: _showScrollToBottom ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_showScrollToBottom,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 80), // 🔹 بالا بردن دکمه
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.grey.shade800,
                onPressed: _scrollToBottom,
                child: const Icon(
                  Icons.arrow_downward,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}
