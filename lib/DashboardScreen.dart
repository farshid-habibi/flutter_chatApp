import 'dart:async';
import 'dart:convert';
import 'dart:convert' as RealtimePayloadType;
import 'dart:io';
import 'dart:ui';
import 'package:Talkify/Screens/Chat/DynamicSnackBar.dart';
import 'package:Talkify/Screens/Chat/FancySnackBarState.dart';
import 'package:Talkify/Screens/Chat/chat_page.dart';
import 'package:Talkify/Screens/Welcome/welcome_screen.dart';
import 'package:Talkify/core/SettingsScreen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:image_picker/image_picker.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:just_audio/just_audio.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _savedUsers = [];
  bool _isLoading = false;
  Timer? _debounce;
  Map<String, int> _unreadCounts = {};
  late RealtimeChannel _unreadChannel;
  late StreamSubscription _connectionSubscription;
  bool _isOffline = false;
  bool _isPickingAvatar = false;
  bool _isOpeningChat = false;

  static const MethodChannel _soundChannel = MethodChannel(
    'com.example.flutter/notifications',
  );

  Future<void> _playNotificationSound() async {
    try {
      await _soundChannel.invokeMethod('playNotification');
    } catch (e) {
      print("❌ Error playing notification sound: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _checkAndRefreshSession();
    _loadSavedUsers();
    _loadCurrentUserProfile();
    _loadUnreadCounts();
    _setupRealtimeUnreadCounts();
    _startInternetListener();
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

  void _setupRealtimeUnreadCounts() {
    final currentUserId = supabase.auth.currentUser!.id;

    supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .neq('sender_id', currentUserId)
        .listen((event) {
          _loadUnreadCounts();
        });

    supabase
        .from('message_reads')
        .stream(primaryKey: ['id'])
        .eq('user_id', currentUserId)
        .listen((event) {
          _loadUnreadCounts();
        });
  }

  Future<void> _loadUnreadCounts() async {
    final currentUserId = supabase.auth.currentUser!.id;

    final response = await supabase.rpc(
      'get_unread_counts',
      params: {'current_user_id': currentUserId},
    );

    final countsMap = <String, int>{};

    if (response != null && response is List) {
      for (final r in response) {
        final userId = r['user_id'] as String?;
        final unreadCount = (r['unread_count'] ?? 0) as int;
        if (userId != null && unreadCount > 0) {
          countsMap[userId] = unreadCount;
        }
      }
    }

    bool badgeIncreased = false;
    countsMap.forEach((userId, newCount) {
      final oldCount = _unreadCounts[userId] ?? 0;
      if (newCount > oldCount) {
        badgeIncreased = true;
      }
    });

    setState(() {
      _unreadCounts = countsMap;
    });

    if (badgeIncreased) {
      _playNotificationSound();
    }
  }

  Future<void> _checkAndRefreshSession() async {
    final hasInternet = await InternetConnectionChecker().hasConnection;
    final session = supabase.auth.currentSession;

    if (session == null) {
      if (!mounted) return;
      if (hasInternet) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
      return;
    }

    if (hasInternet) {
      try {
        await supabase.auth.refreshSession();
      } catch (e) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _loadSavedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('savedUsers');
    if (saved != null) {
      setState(() {
        _savedUsers = List<Map<String, dynamic>>.from(jsonDecode(saved));
      });
    }
  }

  Future<void> _saveUser(Map<String, dynamic> user) async {
    if (!_savedUsers.any((u) => u['id'] == user['id'])) {
      _savedUsers.add(user);
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('savedUsers', jsonEncode(_savedUsers));
      setState(() {});

      showCustomSnackBar(
        context,
        message: '${user['username']} added to your list',
        background: Colors.black87,
        icon: Icons.check_circle_outline,
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

    double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: keyboardHeight + 20,
          child: Material(
            color: Colors.transparent,
            child: FancySnackBar(
              message: message,
              icon: icon,
              duration: duration,
              gradientColors:
                  gradientColors ??
                  [const Color(0xFF6A0DAD), const Color(0xFF00BFFF)],
              onClose: () => overlayEntry.remove(),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);
  }

  Future<void> _toggleSavedUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();

    final isSaved = _savedUsers.any((u) => u['id'] == user['id']);

    if (isSaved) {
      // AnimatedSnackBar.show(
      //   context,
      //   message: '${user['username']} removed from your saved list',
      //   background: Colors.redAccent,
      //   icon: Icons.delete_outline,
      // );
    } else {
      _savedUsers.add(user);
      DynamicSnackBar.show(
        context,
        message: '${user['username']} added to your saved list',
        background: Colors.green,
        icon: Icons.check_circle_outline,
      );
    }

    await prefs.setString('savedUsers', jsonEncode(_savedUsers));
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _isLoading = true);

      try {
        if (query.isEmpty) {
          setState(() => _searchResults = []);
        } else {
          final response = await supabase
              .from('profiles')
              .select('id, username, email,avatar_url,description')
              .ilike('username', '%$query%');

          setState(
            () => _searchResults = List<Map<String, dynamic>>.from(response),
          );
          print(response);
        }
      } catch (e) {
        print("❌ Error searching users: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isPickingAvatar) return;
    _isPickingAvatar = true;
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      final user = supabase.auth.currentUser;
      if (user == null) return;

      final fileExt = path.extension(pickedFile.path);
      final fileName = "${user.id}$fileExt";
      final filePath = "avatars/$fileName";

      await supabase.storage
          .from('avatars')
          .upload(
            filePath,
            File(pickedFile.path),
            fileOptions: const FileOptions(upsert: true),
          );
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(filePath);

      await supabase
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id);

      setState(() {
        user.userMetadata?['avatar_url'] = publicUrl;
      });
    } catch (e) {
      print("❌ Error uploading avatar: $e");
    } finally {
      _isPickingAvatar = false;
    }
  }

 

  Future<void> _openChat(String otherUserId) async {
    if (_isOpeningChat) return;
    _isOpeningChat = true;

    try {
      final currentUserId = supabase.auth.currentUser!.id;

      final existingRoom = await supabase
          .from('rooms')
          .select('id')
          .or(
            'name.eq.private_${currentUserId}_$otherUserId,name.eq.private_${otherUserId}_$currentUserId',
          )
          .maybeSingle();

      String roomId;
      if (existingRoom != null) {
        roomId = existingRoom['id'];
      } else {
        final newRoom = await supabase
            .from('rooms')
            .insert({
              'name': 'private_${currentUserId}_$otherUserId',
              'creator_id': currentUserId,
            })
            .select()
            .single();

        roomId = newRoom['id'];

        await supabase.from('room_members').insert([
          {'room_id': roomId, 'user_id': currentUserId},
          {'room_id': roomId, 'user_id': otherUserId},
        ]);
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(roomId: roomId, otherUserId: otherUserId),
        ),
      );

      _unreadCounts[otherUserId] = 0;
      await _loadUnreadCounts();
    } catch (e) {
      print("❌ Failed to open chat: $e");
    }

    _isOpeningChat = false;
  }

  Future<void> _loadCurrentUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final profile = await supabase
        .from('profiles')
        .select('username, avatar_url,description')
        .eq('id', userId)
        .single();
    if (profile != null && mounted) {
      setState(() {
        supabase.auth.currentUser?.userMetadata?['username'] =
            profile['username'];
        supabase.auth.currentUser?.userMetadata?['avatar_url'] =
            profile['avatar_url'] ?? '';
        supabase.auth.currentUser?.userMetadata?['description'] =
            profile['description'] ?? '';
      });
    }
  }

  @override
  void dispose() {
    _unreadChannel.unsubscribe();
    _debounce?.cancel();
    _connectionSubscription.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 150,
            width: 150,
            child: Image.asset("assets/images/searching_profile.gif"),
          ),
          const SizedBox(height: 16),
          const Text(
            "No users found",
            style: TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Try searching for someone...",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    Color color = Colors.white,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: TweenAnimationBuilder(
        duration: const Duration(milliseconds: 350),
        tween: Tween<double>(begin: 0, end: 1),
        curve: Curves.easeOut,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(-20 * (1 - value), 0),
            child: child,
          ),
        ),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1.1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    final combinedUsers = [
      ..._savedUsers,
      ..._searchResults.where(
        (u) => !_savedUsers.any((saved) => saved['id'] == u['id']),
      ),
    ];
    return WillPopScope(
      // This is required: return false to disable back button
      onWillPop: () async {
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          centerTitle: true,
          title: const Text(
            "Talkify",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.white,
              fontFamily:
                  "Poppins",
            ),
          ),
          backgroundColor: const Color.fromARGB(255, 40, 51, 71)
        ),

        drawer: Drawer(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(40),
              bottomRight: Radius.circular(40),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withOpacity(0.15),
                      width: 1.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 60),

                    Center(
                      child: Column(
                        children: [
                          // Avatar
                          GestureDetector(
                            onTap: _pickAndUploadAvatar,
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueAccent.withOpacity(0.45),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                               child: CircleAvatar(
                                radius: 45,
                                backgroundImage:
                                    user?.userMetadata?['avatar_url'] != null
                                    ? NetworkImage(
                                        user!.userMetadata!['avatar_url'],
                                      )
                                    : null,
                                backgroundColor: Colors.white.withOpacity(0.15),
                                child: user?.userMetadata?['avatar_url'] == null
                                    ? Text(
                                        (user?.userMetadata?['username'] ??
                                                'U')[0]
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            user?.userMetadata?['username'] ?? "User",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Email
                          Text(
                            user?.email ?? "",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(height: 2),

                          // Description
                          Text(
                            user?.userMetadata?['description'] ?? "",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 25),
                        ],
                      ),
                    ),

                    Divider(color: Colors.white.withOpacity(0.15)),

                    const SizedBox(height: 10),

                    _drawerItem(
                      icon: Icons.settings_rounded,
                      label: "Settings",
                      onTap: () async {
                        Navigator.pop(context);
                        final changed = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                        if (changed == true) {
                          _loadCurrentUserProfile();
                          setState(() {});
                        }
                      },
                    ),

                    _drawerItem(
                      icon: Icons.logout_rounded,
                      label: "Logout",
                      color: Colors.redAccent,
                      onTap: () async {
                        await supabase.auth.signOut();
                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WelcomeScreen(),
                          ),
                          (route) => false,
                        );
                      },
                    ),

                    const Spacer(),

                    Padding(
                      padding: const EdgeInsets.only(bottom: 30),
                      child: Center(
                        child: Text(
                          "Version 1.0.0",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/background.png"),
              fit: BoxFit.cover,
            ),
          ),
          child: Column(
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

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              Expanded(
                child: combinedUsers.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: combinedUsers.length,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          final u = combinedUsers[index];
                          final unread = _unreadCounts[u['id']] ?? 0;

                          final isSavedUser = _savedUsers.any(
                            (saved) => saved['id'] == u['id'],
                          );

                          final userItem = TweenAnimationBuilder(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOut,
                            tween: Tween<double>(begin: 0, end: 1),
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: Opacity(opacity: value, child: child),
                              );
                            },
                            child: GestureDetector(
                              onLongPress: () => _toggleSavedUser(u),
                              onTap: () => _openChat(u['id']),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.15),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 12,
                                      sigmaY: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 54,
                                          height: 54,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.blueAccent
                                                    .withOpacity(0.5),
                                                blurRadius: 15,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              50,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: u['avatar_url'] ?? "",
                                              fit: BoxFit.cover,
                                              width: 54,
                                              height: 54,
                                              
                                              placeholder: (context, url) =>
                                                  Container(
                                                    width: 54,
                                                    height: 54,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withOpacity(0.12),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        (u['username'] ??
                                                                'U')[0]
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 20,
                                                          color: Colors.white70,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              errorWidget:
                                                  (
                                                    context,
                                                    url,
                                                    error,
                                                  ) => Container(
                                                    width: 54,
                                                    height: 54,
                                                    decoration:
                                                        const BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color: Colors.grey,
                                                        ),
                                                    child: const Icon(
                                                      Icons.person,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                              fadeInDuration: const Duration(
                                                milliseconds: 250,
                                              ),
                                              fadeOutDuration: const Duration(
                                                milliseconds: 100,
                                              ),
                                            ),
                                          ),
                                       
                                       
                                       
                                       
                                        ),

                                        const SizedBox(width: 16),

                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u['username'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                u['description'] ?? "",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.white
                                                      .withOpacity(0.6),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            const Icon(
                                              Icons.chat_bubble_rounded,
                                              color: Colors.blueAccent,
                                              size: 30,
                                            ),
                                            if (unread > 0)
                                              Positioned(
                                                right: 2,
                                                top: -6,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.redAccent,
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.redAccent
                                                            .withOpacity(0.5),
                                                        blurRadius: 8,
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    unread.toString(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                          );

                          if (isSavedUser) {
                            return Dismissible(
                              key: Key(u['id']),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (direction) async {
                                final result = await showDialog<bool>(
                                  context: context,
                                  barrierDismissible: true,
                                  builder: (context) {
                                    return Center(
                                      child: TweenAnimationBuilder(
                                        tween: Tween<double>(
                                          begin: 0.8,
                                          end: 1,
                                        ),
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: Curves.easeOutBack,
                                        builder: (context, scale, child) {
                                          return Transform.scale(
                                            scale: scale,
                                            child: child,
                                          );
                                        },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                              sigmaX: 18,
                                              sigmaY: 18,
                                            ),
                                            child: Container(
                                              width: 300,
                                              padding: const EdgeInsets.all(22),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  0.07,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(25),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withOpacity(0.15),
                                                  width: 1.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.35),
                                                    blurRadius: 25,
                                                    offset: const Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          14,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Colors.redAccent
                                                          .withOpacity(0.25),
                                                    ),
                                                    child: const Icon(
                                                      Icons.delete,
                                                      color: Colors.redAccent,
                                                      size: 34,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 18),
                                                  const Text(
                                                    "Remove User?",
                                                    style: TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    "Are you sure you want to remove ${u['username']}?",
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      color: Colors.white
                                                          .withOpacity(0.75),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 28),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                false,
                                                              ),
                                                          child: Text(
                                                            "Cancel",
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                    0.9,
                                                                  ),
                                                              fontSize: 16,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 14,
                                                                ),
                                                            backgroundColor:
                                                                Colors
                                                                    .redAccent,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    14,
                                                                  ),
                                                            ),
                                                          ),
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                true,
                                                              ),
                                                          child: const Text(
                                                            "Remove",
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
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
                                    );
                                  },
                                );

                                if (result == true) {
                                  _savedUsers.removeWhere(
                                    (saved) => saved['id'] == u['id'],
                                  );
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setString(
                                    'savedUsers',
                                    jsonEncode(_savedUsers),
                                  );
                                  if (mounted) setState(() {});
                                  return true;
                                }

                                return false;
                              },
                              background: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.45),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                alignment: Alignment.centerRight,
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              child: userItem,
                            );
                          } else {
                            return userItem;
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
