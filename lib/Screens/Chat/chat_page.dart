import 'dart:async';
import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:io';
import 'dart:ui';
import 'package:bubble/bubble.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/Screens/Chat/FancySnackBarState.dart';
import 'package:flutter_application_1/Screens/Chat/SlideTransitionWidget.dart';
import 'package:flutter_application_1/Screens/Chat/SmartTextField%20.dart';
import 'package:flutter_application_1/Screens/Chat/WhatsAppVoiceBubble.dart';
import 'package:flutter_application_1/core/supabase_client.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:record/record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';

class ChatPage extends StatefulWidget {
  final String roomId;
  final String otherUserId;

  const ChatPage({super.key, required this.roomId, required this.otherUserId});

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
  bool _hasScrolledToLastMessage = false;
  String _currentUserId = '';
  bool _isUploading = false;
  String? _chatUserName;
  late RealtimeChannel _channel;
  File? _uploadingMediaFile;
  final Map<String, GlobalKey> messageKeys = {};
  Map<String, bool> highlightedMessages = {};
  bool _showScrollToBottom = false;
  String? _chatUserAvatar;
  bool _chatUserOnline = false;
  String? _chatUserLastSeen;
  bool _isSelectionMode = false;
  Set<String> _selectedMessageIds = {};
  List<Map<String, dynamic>> messages = [];
  bool _isMenuOpen = false;
  List<Map<String, dynamic>> _localMessages = [];
  bool _isUploadingMedia = false;
  bool _isSearchMode = false;
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  final Map<String, AudioPlayer> _audioPlayers = {};

  final Map<String, AnimationController> _animationControllers = {};
  Map<String, bool> _expandedMessages = {};
  late FlutterSoundRecorder _recorder;
  bool _isRecording = false;
  late String _recordedFilePath;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlaying = false;
  String? _currentlyPlayingId;
  bool _isRecorderInitialized = false;
  late RealtimeChannel _unreadChannel;
  late StreamSubscription _connectionSubscription;
  bool _isOffline = false;
  bool _isSending = false;

  Widget buildMessageContent(Map<String, dynamic> msg) {
    final text = msg['content'] ?? '';
    final isMine = (msg['sender_id'] ?? '') == _currentUserId;
    const int previewLength = 80;
    final bool needsTruncate = text.length > previewLength;
    final bool isExpanded = _expandedMessages[msg['id']] ?? false;

    final displayText = (!needsTruncate || isExpanded)
        ? text
        : '${text.substring(0, previewLength)}...';

    Widget buildStatusIcon() {
      final status = (msg['status'] ?? 'sent').toString().toLowerCase().trim();
      IconData icon;
      Color color;

      if (status == 'read') {
        icon = Icons.done_all;
        color = Colors.blueAccent;
      } else if (status == 'delivered') {
        icon = Icons.done_all;
        color = Colors.white54;
      } else {
        icon = Icons.done;
        color = Colors.white54;
      }

      return Icon(icon, size: 16, color: color);
    }

    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          displayText,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.justify,
        ),
        // دکمه Show more / Show less
        if (needsTruncate)
          GestureDetector(
            onTap: () {
              setState(() {
                _expandedMessages[msg['id']] = !isExpanded;
              });
            },
            child: Text(
              isExpanded ? "Show less" : "Show more",
              style: const TextStyle(color: Colors.blueAccent, fontSize: 12),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMine) buildStatusIcon(),
            const SizedBox(width: 4),
            Text(
              msg['created_at']?.toString().substring(11, 16) ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

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

  String _formatLastSeen(String? isoTime) {
    if (isoTime == null) return 'Unknown';
    final dt = DateTime.parse(isoTime).toLocal();
    final now = DateTime.now();

    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${dt.year}/${dt.month}/${dt.day}';
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

  Map<String, bool> _expandedCaptions = {};

  Widget _buildMediaMessage(
    BuildContext context,
    Map<String, dynamic> msg,
    bool isMine,
  ) {
    final caption = msg['content'] ?? '';
    final int previewLength = 80;
    final bool needsTruncate = caption.length > previewLength;
    final bool isExpanded = _expandedCaptions[msg['id']] ?? false;

    final displayText = (!needsTruncate || isExpanded)
        ? caption
        : '${caption.substring(0, previewLength)}...';

    final double maxCardWidth = MediaQuery.of(context).size.width * 0.65;
    final bool isUploading =
        (msg['status']?.toString().toLowerCase() ?? '') == 'uploading';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: maxCardWidth,
        child: Card(
          color: isMine ? Colors.purple : Colors.indigo.shade800,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: Color.fromARGB(255, 85, 220, 155),
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg['media_url'] != null)
                GestureDetector(
                  onTap: () => _openMediaFullScreen(
                    msg['media_url'],
                    msg['is_video'] == true,
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        msg['is_video'] == true
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
                                  return AspectRatio(
                                    aspectRatio:
                                        controller.value.aspectRatio == 0
                                        ? 16 / 9
                                        : controller.value.aspectRatio,
                                    child: VideoPlayer(controller),
                                  );
                                },
                              )
                            : msg['media_url'].toString().startsWith('/')
                            ? Image.file(
                                File(msg['media_url']),
                                width: maxCardWidth,
                                height: 400,
                                fit: BoxFit.cover,
                              )
                            : CachedNetworkImage(
                                imageUrl: msg['media_url'],
                                width: maxCardWidth,
                                height: 400,
                                fit: BoxFit.cover,
                              ),

                        if (isUploading)
                          Container(
                            width: maxCardWidth,
                            height: 400,
                            color: Colors.black38,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: Colors.white70,
                                    strokeWidth: 3,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'در حال آپلود...',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        if (msg['is_video'] == true && !isUploading)
                          const Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 64,
                          ),
                      ],
                    ),
                  ),
                ),

              if ((caption).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayText,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.justify,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      if (needsTruncate)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _expandedCaptions[msg['id']] = !isExpanded;
                            });
                          },
                          child: Text(
                            isExpanded ? "show less" : " show more",
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      msg['created_at']?.toString().substring(11, 16) ?? '',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isMine)
                      Builder(
                        builder: (context) {
                          final status = (msg['status'] ?? 'sent')
                              .toString()
                              .toLowerCase()
                              .trim();
                          IconData icon;
                          Color color;

                          if (status == 'uploading') {
                            icon = Icons.cloud_upload;
                            color = Colors.orangeAccent;
                          } else if (status == 'read') {
                            icon = Icons.done_all;
                            color = Colors.blueAccent;
                          } else if (status == 'delivered') {
                            icon = Icons.done_all;
                            color = Colors.white54;
                          } else {
                            icon = Icons.done;
                            color = Colors.white54;
                          }
                          return Icon(icon, size: 16, color: color);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setUserOnlineStatus(bool isOnline) async {
    try {
      await _supabase
          .from('profiles')
          .update({
            'online': isOnline,
            'last_seen': DateTime.now().toIso8601String(),
          })
          .eq('id', _currentUserId);
    } catch (e) {
      debugPrint("❌ Failed to update online status: $e");
    }
  }

  Future<void> _initRecorder() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      print("Microphone permission denied");
      return;
    }

    await _recorder.openRecorder();
    _isRecorderInitialized = true;
    print("Recorder initialized");
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) return;

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

    await _recorder.startRecorder(toFile: path, codec: Codec.aacADTS);

    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecorderInitialized) return;

    final path = await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
    });

    print("Recording saved at: $path");

    if (path != null) {
      final file = File(path);
      await _uploadVoiceToSupabase(file);
    }
  }

  void _startInternetListener() {
    _connectionSubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      bool hasInternet = await InternetConnectionChecker().hasConnection;

      if (!hasInternet && !_isOffline) {
        setState(() => _isOffline = true);
      } else if (hasInternet && _isOffline) {
        setState(() => _isOffline = false);
      }
    });
  }

  Future<void> _uploadVoiceToSupabase(File file) async {
    final fileBytes = await file.readAsBytes();
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';

    try {
      final response = await supabase.storage
          .from('voice')
          .uploadBinary(fileName, fileBytes);
      print('Upload successful: $fileName');
    } catch (e) {
      print('Upload failed: $e');
    }

    final fileExt = file.path.split('.').last;

    if (!await file.exists()) {
      print("File does not exist at path: ${file.path}");
      return;
    }

    try {
      final publicUrl = _supabase.storage.from('voice').getPublicUrl(fileName);

      print("Public URL: $publicUrl");

      await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_id': _currentUserId,
        'content': '[Voice]',
        'media_url': publicUrl,
        'is_video': false,
        'is_voice': true,
        'status': 'sent',
        'created_at': DateTime.now().toIso8601String(),
      });

      // بروزرسانی UI
      setState(() {
        messages.add({
          'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
          'room_id': widget.roomId,
          'sender_id': _currentUserId,
          'content': '[Voice]',
          'media_url': publicUrl,
          'is_video': false,
          'is_voice': true,
          'status': 'sent',
          'created_at': DateTime.now().toIso8601String(),
        });
      });

      _scrollToBottom();
    } catch (e, st) {
      print("Upload or DB error: $e\n$st");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to upload voice')));
    }
  }

  Future<void> _playVoice(String messageId, String url) async {
    try {
      if (_currentlyPlayingId == messageId && _isPlaying) {
        await _player.stopPlayer();
        setState(() {
          _isPlaying = false;
          _currentlyPlayingId = null;
        });
        return;
      }

      if (_isPlaying) {
        await _player.stopPlayer();
      }

      await _player.startPlayer(
        fromURI: url,
        codec: Codec.aacADTS,
        whenFinished: () {
          setState(() {
            _isPlaying = false;
            _currentlyPlayingId = null;
          });
        },
      );

      setState(() {
        _isPlaying = true;
        _currentlyPlayingId = messageId;
      });
    } catch (e) {
      print('❌ خطا در پخش ویس: $e');
    }
  }

  Future<void> _openAudioModules() async {
    await _recorder.openRecorder();
    await _player.openPlayer();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
  }

  @override
  void initState() {
    super.initState();
    _startInternetListener();
    WidgetsBinding.instance.addObserver(this);
    _recorder = FlutterSoundRecorder();
    _initRecorder();
    _player.openPlayer();
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
    _loadUserInfo();
    _setUserOnlineStatus(true);

    _messageStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('created_at', ascending: true)
        .map((data) => data.cast<Map<String, dynamic>>());

    _channel = _supabase.channel('room_${widget.roomId}_realtime');
    _channel.subscribe();

    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _markMessagesAsRead();
    _recorder.closeRecorder();
    _player.closePlayer();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    for (final p in _audioPlayers.values) {
      p.dispose();
    }

    _channel.unsubscribe();

    for (final future in _videoControllers.values) {
      future.then((controller) => controller.dispose());
    }

    for (final controller in _animationControllers.values) {
      controller.dispose();
    }
    _setUserOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_currentUserId.isEmpty) return;

    if (state == AppLifecycleState.resumed) {
      _setUserOnlineStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setUserOnlineStatus(false);
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final unreadMessages = await _supabase
          .from('messages')
          .select('id')
          .eq('room_id', widget.roomId)
          .neq('sender_id', _currentUserId)
          .neq('status', 'read'); // فقط پیام‌هایی که خوانده نشده‌اند

      for (final msg in unreadMessages) {
        await _supabase.from('message_reads').upsert({
          'message_id': msg['id'],
          'user_id': _currentUserId,
        });

        await _supabase
            .from('messages')
            .update({'status': 'read'}) // 👈 وضعیت را تغییر بده
            .eq('id', msg['id']);
      }
    } catch (e) {
      print("❌ Error marking messages as read: $e");
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      debugPrint('🔹 Loading user info for ID: ${widget.otherUserId}');

      final data = await _supabase
          .from('profiles')
          .select('username, avatar_url,online,last_seen')
          .eq('id', widget.otherUserId)
          .maybeSingle();
      if (_chatUserOnline) {
        await _supabase
            .from('messages')
            .update({'status': 'delivered'})
            .eq('room_id', widget.roomId)
            .eq('sender_id', _currentUserId)
            .eq('status', 'sent');
      }

      debugPrint('📦 User data: $data');

      setState(() {
        _chatUserName = data?['username'] ?? 'Chat Room';
        _chatUserAvatar = data?['avatar_url'];
        _chatUserOnline = data?['online'] == true || data?['online'] == 'true';
        _chatUserLastSeen = data?['last_seen'];
      });
    } catch (e, st) {
      debugPrint('❌ Error loading user info: $e');
      debugPrint(st.toString());
      setState(() {
        _chatUserName = 'Chat Room';
        _chatUserAvatar = null;
        _chatUserOnline = false;
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
    final tempId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = {
      'id': tempId,
      'room_id': widget.roomId,
      'sender_id': _currentUserId,
      'content': caption ?? '',
      'media_url': file.path,
      'is_video': isVideo,
      'status': 'uploading',
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      messages.add(tempMessage);
      _isUploadingMedia = true;
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
        'status': 'sent',
      });

      setState(() {
        final index = messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          messages[index]['media_url'] = mediaUrl;
          messages[index]['status'] = 'sent';
          messages[index]['id'] =
              'server_${DateTime.now().millisecondsSinceEpoch}';
        }
        _isUploadingMedia = false;
      });

      _showFancySnackBar(
        message: "Image uploaded successfully!",
        icon: Icons.check_circle,
        colors: [Colors.green, Colors.lightGreenAccent],
      );
      _scrollToBottom();
    } catch (e) {
      setState(() {
        final index = messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) messages[index]['status'] = 'failed';
        _isUploadingMedia = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to upload media')));
    }
  }

  void _showFancySnackBar({
    required String message,
    required IconData icon,
    required List<Color> colors,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FancySnackBar(
        message: message,
        icon: icon,
        duration: const Duration(seconds: 2),
        gradientColors: colors,
        onClose: () => overlayEntry.remove(),
      ),
    );

    overlay?.insert(overlayEntry);
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
    if (_isSending) return;
    _isSending = true;
    setState(() {});
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
        'status': 'sent',
        'created_at': DateTime.now().toIso8601String(),
        if (_replyingTo != null) 'reply_to': _replyingTo!['id'],
      });
      setState(() {
        _replyingTo = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
    } finally {
      _isSending = false;
      setState(() {});
    }

    _controller.clear();
    _scrollToBottom();
  }

  Future<String?> _showCaptionBottomSheet() async {
    final captionController = TextEditingController();

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.2,
          maxChildSize: 0.7,
          builder: (context, scrollController) {
            return TweenAnimationBuilder(
              tween: Tween<double>(begin: 0.8, end: 1),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.4,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Column(
                      children: [
                        const Text(
                          "Add a Caption",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TextField(
                            controller: captionController,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText:
                                  "Write something about your image or video...",
                              hintStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text(
                                "Cancel",
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                              ),
                              onPressed: () => Navigator.pop(
                                context,
                                captionController.text.trim(),
                              ),
                              child: const Text("Send"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendMedia() async {
    try {
      final XFile? pickedFile = await _picker.pickMedia();
      if (pickedFile == null) return;

      final captionController = TextEditingController();

      final caption = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder(
                tween: Tween<double>(begin: 0.8, end: 1),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 25,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 500),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blueAccent.withOpacity(0.25),
                                ),
                                child: const Icon(
                                  Icons.edit_note,
                                  color: Colors.blueAccent,
                                  size: 34,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                "Add a Caption",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 250,
                                child: SmartTextField(
                                  controller: captionController,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, null),
                                      child: const Text(
                                        "Cancel",
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed: () => Navigator.pop(
                                        context,
                                        captionController.text.trim(),
                                      ),
                                      child: const Text(
                                        "Send",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

      if (caption == null) return;

      final File file = File(pickedFile.path);
      final fileExt = pickedFile.path.split('.').last.toLowerCase();
      final isVideo = ['mp4', 'mov', 'avi', 'mkv'].contains(fileExt);

      setState(() {
        _isUploading = true;
        _uploadingMediaFile = file;
      });

      await _uploadMediaWithCaption(file, isVideo, caption);
      _scrollToBottom();
    } catch (e) {
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
    try {
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
          const PopupMenuItem<String>(
            value: 'multi_delete',
            child: Row(
              children: [
                Icon(Icons.check_box, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Multiple selection',
                  style: TextStyle(color: Colors.white),
                ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        color: Colors.black.withOpacity(0.8),
      );

      if (!mounted) return; // اگر widget حذف شده بود
      if (selected == null) return; // منو بسته شد بدون انتخاب

      if (selected == 'copy') {
        Clipboard.setData(ClipboardData(text: msg['content'] ?? ''));
        showCustomSnackBar(
          context,
          message: 'Message copied ✅',
          background: Colors.black87,
          icon: Icons.copy_outlined,
        );
      } else if (selected == 'multi_delete') {
        setState(() {
          _isSelectionMode = true;
          _selectedMessageIds.clear();
          _selectedMessageIds.add(msg['id']);
        });
      } else if (selected == 'delete') {
        FocusScope.of(context).unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        try {
          await _supabase.from('messages').delete().eq('id', msg['id']);

          setState(() {
            messages.removeWhere((m) => m['id'] == msg['id']);
            _messageStream = _supabase
                .from('messages')
                .stream(primaryKey: ['id'])
                .eq('room_id', widget.roomId)
                .order('created_at', ascending: true)
                .map((data) => data.cast<Map<String, dynamic>>());
          });

          showCustomSnackBar(
            context,
            message: 'Message deleted ✅',
            background: Colors.black87,
            icon: Icons.check_circle_outline,
          );
        } catch (e) {
          showCustomSnackBar(
            context,
            message: 'Failed to delete message ❌',
            background: Colors.red.shade900,
            icon: Icons.error_outline,
          );
        }
      } else if (selected == 'reply') {
        setState(() {
          _replyingTo = msg;
        });
      }
    } catch (e) {
      debugPrint("Error showing message menu: $e");
    }
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    try {
      await _supabase
          .from('messages')
          .delete()
          .inFilter('id', _selectedMessageIds.toList());

      setState(() {
        _isSelectionMode = false;
        _selectedMessageIds.clear();
      });

      setState(() {
        _messageStream = _supabase
            .from('messages')
            .stream(primaryKey: ['id'])
            .eq('room_id', widget.roomId)
            .order('created_at', ascending: true)
            .map((data) => data.cast<Map<String, dynamic>>());
      });

      showCustomSnackBar(
        context,
        message: 'Selected messages deleted ',
        background: Colors.black87,
        icon: Icons.check_circle_outline,
      );
    } catch (e) {
      showCustomSnackBar(
        context,
        message: 'Failed to delete messages ',
        background: Colors.red.shade900,
        icon: Icons.error_outline,
      );
    }
  }

  void showCustomSnackBar(
    BuildContext context, {
    required String message,
    IconData icon = Icons.info_outline,
    Duration duration = const Duration(seconds: 3),
    List<Color>? gradientColors,
    required Color background,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FancySnackBar(
        message: message,
        icon: icon,
        duration: duration,
        gradientColors:
            gradientColors ??
            [Color(0xFF6A0DAD), Color(0xFF00BFFF)], // بنفش به آبی
        onClose: () => overlayEntry.remove(), // اینجا remove می‌کنیم
      ),
    );

    overlay.insert(overlayEntry);
  }

  Color _getBubbleColor(bool isMine, Map<String, dynamic> msg) {
    if (msg['media_url'] != null) {
      return Colors.transparent;
    }
    return isMine ? Color.fromARGB(255, 131, 48, 129) : Colors.indigo.shade800;
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
    await Future.delayed(const Duration(milliseconds: 700));
    overlayEntry.remove();
  }

  Widget _buildEmptyChatUI() {
    return Center(
      child: AnimatedOpacity(
        opacity: 1,
        duration: Duration(milliseconds: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 18,
                    spreadRadius: 2,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 80,
                color: Colors.blue.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "No messages yet",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Send the first message to start the conversation ✨",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 30),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.blue.shade50,
              ),
              child: Text(
                "Say hello 👋",
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.blue.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> scrollToMessage(String messageId) async {
    final index = messageIndexes[messageId];
    if (index == null) return;

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

  void _showUserProfileSheet(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) {
          return const SizedBox.shrink();
        },
        transitionsBuilder: (context, animation, _, child) {
          final fade = Tween(
            begin: 0.0,
            end: 1.0,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

          final slide = Tween(begin: 40.0, end: 0.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          );

          final scale = Tween(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          );

          return Scaffold(
            backgroundColor: Colors.black.withOpacity(fade.value * 0.55),
            body: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, slide.value),
                  child: Transform.scale(
                    scale: scale.value,
                    child: _buildUltraProfileCard(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUltraProfileCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.18),
                Colors.white.withOpacity(0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.7),
                blurRadius: 40,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: Colors.purpleAccent.withOpacity(0.4),
                blurRadius: 60,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Avatar with Pulse Animation ---
              TweenAnimationBuilder(
                duration: const Duration(milliseconds: 1800),
                curve: Curves.easeInOut,
                tween: Tween<double>(begin: 0.95, end: 1.05),
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.8),
                        blurRadius: 25,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: Colors.purpleAccent.withOpacity(0.5),
                        blurRadius: 40,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 65,
                    backgroundImage: _chatUserAvatar != null
                        ? NetworkImage(_chatUserAvatar!)
                        : null,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    child: _chatUserAvatar == null
                        ? Icon(
                            Icons.person,
                            size: 65,
                            color: Colors.white.withOpacity(0.6),
                          )
                        : null,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                _chatUserName ?? "Unknown User",
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                "Swipe down or tap to close",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveMessagesCache() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('cached_messages', jsonEncode(messages));
  }

  Future<void> _loadMessagesCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_messages');
    if (cached != null) {
      final cachedList = List<Map<String, dynamic>>.from(jsonDecode(cached));
      setState(() {
        messages = cachedList;
      });
    }
  }

  Widget _buildMessagesList(List<Map<String, dynamic>> messageList) {
    for (var i = 0; i < messageList.length; i++) {
      final msg = messageList[i];
      final messageId = msg['id'];

      // ذخیره کلیدها و اندیس‌ها
      messageIndexes.putIfAbsent(messageId, () => i);
      messageKeys.putIfAbsent(messageId, () => GlobalKey());

      _animationControllers.putIfAbsent(
        messageId,
        () => AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 400),
        )..forward(),
      );
    }

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.all(12),
      itemCount: messageList.length,
      reverse: false,
      itemBuilder: (context, index) {
        final msg = messageList[index];
        final messageId = msg['id'];
        final isMine = msg['sender_id'] == _currentUserId;
        final animationController = _animationControllers[messageId]!;
        final isVoice = msg['is_voice'] == true;
        final mediaUrl = msg['media_url'] ?? '';

        return FadeTransition(
          key: ValueKey(messageId),
          opacity: animationController.drive(Tween(begin: 0.0, end: 1.0)),
          child: SlideTransition(
            position: animationController.drive(
              Tween(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOut)),
            ),
            child: GestureDetector(
              onLongPressStart: (details) =>
                  _showMessageMenu(details.globalPosition, msg, isMine),
              onTap: () {
                if (_isSelectionMode) {
                  setState(() {
                    if (_selectedMessageIds.contains(msg['id'])) {
                      _selectedMessageIds.remove(msg['id']);
                      if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
                    } else {
                      _selectedMessageIds.add(msg['id']);
                    }
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(vertical: 4),
                foregroundDecoration: _selectedMessageIds.contains(msg['id'])
                    ? BoxDecoration(
                        color: const Color.fromARGB(
                          255,
                          22,
                          19,
                          78,
                        ).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        backgroundBlendMode: BlendMode.overlay,
                      )
                    : null,
                padding: highlightedMessages[msg['id']] == true
                    ? const EdgeInsets.all(2)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: highlightedMessages[msg['id']] == true
                      ? Border.all(color: Colors.lightBlueAccent, width: 3)
                      : null,
                  color: highlightedMessages[msg['id']] == true
                      ? Colors.lightBlueAccent.withOpacity(0.1)
                      : Colors.transparent,
                ),
                alignment: isMine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: isVoice && mediaUrl.isNotEmpty
                    ? WhatsAppVoiceBubble(
                        audioUrl: mediaUrl,
                        isMe: isMine,
                        sentTime: DateTime.parse(msg['created_at']),
                      )
                    : msg['media_url'] != null
                    ? _buildMediaMessage(context, msg, isMine)
                    : Bubble(
                        nip: isMine ? BubbleNip.rightTop : BubbleNip.leftTop,
                        color: _getBubbleColor(isMine, msg),
                        elevation: 1,
                        child: Column(
                          crossAxisAlignment: isMine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (msg['reply_to'] != null)
                              GestureDetector(
                                onTap: () async {
                                  await scrollToMessage(msg['reply_to']);
                                },
                                child: Builder(
                                  builder: (context) {
                                    final replyMsg = messageList.firstWhere(
                                      (m) => m['id'] == msg['reply_to'],
                                      orElse: () => {},
                                    );
                                    if (replyMsg.isEmpty)
                                      return const SizedBox.shrink();

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        replyMsg['content'] ?? '',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            Text(
                              msg['content'] ?? '',
                              style: const TextStyle(color: Colors.white),
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
  }

  Future<File> _cacheAudioFile(String url, String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/$fileName");

      if (!await file.exists()) {
        final response = await http.get(Uri.parse(url));
        await file.writeAsBytes(response.bodyBytes);
      }

      return file;
    } catch (e) {
      debugPrint("Error caching audio file: $e");
      rethrow;
    }
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
          automaticallyImplyLeading: !_isSearchMode,
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: _isSearchMode
              ? Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isSearchMode = false;
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Vazir',
                        ),
                        textDirection: TextDirection.rtl,
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          filled: false,
                          hintText: 'Search...',
                          hintStyle: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Vazir',
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value.trim();
                          });
                        },
                      ),
                    ),
                  ],
                )
              : _isSelectionMode
              ? Text(
                  "${_selectedMessageIds.length} selected message",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Vazir',
                  ),
                )
              : Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showUserProfileSheet(context),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade700,
                        backgroundImage:
                            _chatUserAvatar != null &&
                                _chatUserAvatar!.isNotEmpty
                            ? NetworkImage(_chatUserAvatar!)
                            : const AssetImage(
                                    'assets/images/default_avatar.png',
                                  )
                                  as ImageProvider,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _chatUserName ?? 'Loading...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Vazir',
                          ),
                        ),
                        Text(
                          _chatUserOnline
                              ? 'Online'
                              : 'Last seen: ${_formatLastSeen(_chatUserLastSeen)}',
                          style: TextStyle(
                            color: _chatUserOnline
                                ? Colors.greenAccent
                                : Colors.white70,
                            fontSize: 13,
                            fontFamily: 'Vazir',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          actions: _isSelectionMode
              ? [
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: "حذف پیام‌ها",
                    onPressed: _deleteSelectedMessages,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: "لغو انتخاب",
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = false;
                        _selectedMessageIds.clear();
                      });
                    },
                  ),
                ]
              : [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    color: const Color(0xFF2C2C3A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      if (value == 'search') {
                        setState(() {
                          _isSearchMode = true;
                        });
                      } else if (value == 'clear') {}
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'search',
                        child: Row(
                          children: [
                            Icon(Icons.search, color: Colors.white70),
                            SizedBox(width: 12),
                            Text(
                              'Search',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Vazir',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
        ),

        body: Column(
          children: [
            if (_isOffline)
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * -25), // Slide from top
                      child: child,
                    ),
                  );
                },
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08), // Glass effect
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1.4,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                      child: Row(
                        children: [
                          // 🔥 Glowing red wifi icon
                          Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.15),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withOpacity(0.4),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.wifi_off,
                              color: Colors.redAccent,
                              size: 28,
                            ),
                          ),

                          SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "No Internet Connection",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Waiting for network…",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            if (_isUploadingMedia)
              const LinearProgressIndicator(
                color: Colors.blueAccent,
                minHeight: 4,
              ),

            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _messageStream,
                builder: (context, snapshot) {
                  if (_isOffline) {
                    if (messages.isEmpty) {
                      _loadMessagesCache(); // بارگذاری کش
                    }
                    if (messages.isNotEmpty) {
                      return _buildMessagesList(messages);
                    }
                    return Center(child: Text('No messages available offline'));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyChatUI();
                  }
                  final snapshotMessages = snapshot.data!;
                  // if (messages.isEmpty) {
                  //   return _buildEmptyChatUI();
                  // }
                  if (messages.isEmpty ||
                      messages.length != snapshotMessages.length) {
                    messages = List.from(snapshotMessages);
                    _saveMessagesCache();
                  }
                  final filteredMessages = _searchQuery.isEmpty
                      ? messages
                      : messages.where((msg) {
                          final content = (msg['content'] ?? '').toString();
                          return content.contains(_searchQuery) ||
                              content.contains(_searchQuery.trim());
                        }).toList();

                  for (var i = 0; i < messages.length; i++) {
                    final msg = messages[i];
                    final messageId = msg['id'];

                    messageIndexes.putIfAbsent(messageId, () => i);
                    messageKeys.putIfAbsent(messageId, () => GlobalKey());

                    _animationControllers.putIfAbsent(
                      messageId,
                      () => AnimationController(
                        vsync: this,
                        duration: const Duration(milliseconds: 400),
                      )..forward(),
                    );
                  }

                  if (!_hasScrolledToLastMessage && messages.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_itemScrollController.isAttached) {
                        _itemScrollController.scrollTo(
                          index: messages.length - 1,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                    _hasScrolledToLastMessage = true;
                  }

                  return ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredMessages.length,
                    reverse: false,
                    itemBuilder: (context, index) {
                      final msg = filteredMessages[index];
                      final messageId = msg['id'];
                      final isMine = msg['sender_id'] == _currentUserId;
                      final animationController =
                          _animationControllers[messageId]!;
                      final isVoice = msg['is_voice'] == true;
                      final mediaUrl = msg['media_url'] ?? '';

                      return FadeTransition(
                        key: ValueKey(messageId),
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
                            onTap: () {
                              if (_isSelectionMode) {
                                setState(() {
                                  if (_selectedMessageIds.contains(msg['id'])) {
                                    _selectedMessageIds.remove(msg['id']);
                                    if (_selectedMessageIds.isEmpty)
                                      _isSelectionMode = false;
                                  } else {
                                    _selectedMessageIds.add(msg['id']);
                                  }
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              foregroundDecoration:
                                  _selectedMessageIds.contains(msg['id'])
                                  ? BoxDecoration(
                                      color: const Color.fromARGB(
                                        255,
                                        22,
                                        19,
                                        78,
                                      ).withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      backgroundBlendMode: BlendMode.overlay,
                                    )
                                  : null,
                              padding: highlightedMessages[msg['id']] == true
                                  ? const EdgeInsets.all(2)
                                  : EdgeInsets.zero,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: highlightedMessages[msg['id']] == true
                                    ? Border.all(
                                        color: Colors.lightBlueAccent,
                                        width: 3,
                                      )
                                    : null,
                                color: highlightedMessages[msg['id']] == true
                                    ? Colors.lightBlueAccent.withOpacity(0.1)
                                    : Colors.transparent,
                              ),
                              alignment: isMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: isVoice && mediaUrl.isNotEmpty
                                  ? WhatsAppVoiceBubble(
                                      audioUrl:
                                          mediaUrl, // حتما URL اینترنتی Supabase
                                      isMe: isMine,
                                      sentTime: DateTime.parse(
                                        msg['created_at'],
                                      ),
                                    )
                                  : msg['media_url'] != null
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
                                                  if (replyMsg.isEmpty)
                                                    return const SizedBox.shrink();

                                                  return Container(
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
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.7,
                                            ),
                                            child: buildMessageContent(msg),
                                          ),
                                          const SizedBox(height: 4),
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
                    // نمایش نوار ریپلای (در صورت وجود)
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

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 46, 47, 107),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_controller.text.isEmpty)
                                  Positioned(
                                    left: 0,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Text(
                                        "Message",
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 16,
                                        ),
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                  ),
                                TextField(
                                  controller: _controller,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.right,
                                  textDirection: TextDirection.rtl,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    filled: false,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                  onChanged: (text) {
                                    setState(() {});
                                  },
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 2),

                          if (_controller.text.isEmpty) ...[
                            IconButton(
                              icon: const Icon(
                                Icons.attach_file,
                                color: Colors.white70,
                              ),
                              onPressed: _sendMedia,
                              splashRadius: 20,
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: Icon(
                                _isRecording ? Icons.stop : Icons.mic,
                                color: _isRecording
                                    ? Colors.red
                                    : Colors.white70,
                              ),
                              onPressed: () async {
                                if (!_isRecorderInitialized) {
                                  print(
                                    "Recorder not initialized yet! Waiting...",
                                  );
                                  await _initRecorder(); // اطمینان از آماده بودن رکوردر
                                }

                                if (!_isRecording) {
                                  await _startRecording();
                                } else {
                                  await _stopRecording();
                                }
                              },
                              splashRadius: 20,
                            ),
                          ] else ...[
                            IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: Colors.greenAccent,
                              ),
                              onPressed: _sendMessage,
                              splashRadius: 20,
                            ),
                          ],
                        ],
                      ),
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
              padding: const EdgeInsets.only(bottom: 80),
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
