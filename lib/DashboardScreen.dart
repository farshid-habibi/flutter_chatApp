import 'dart:async';
import 'dart:convert';
import 'dart:convert' as RealtimePayloadType;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/Screens/Chat/FancySnackBarState.dart';
import 'package:flutter_application_1/Screens/Chat/chat_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/Screens/Welcome/welcome_screen.dart';
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
  // final AudioPlayer _player = AudioPlayer();

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
    final session = supabase.auth.currentSession;
    if (session == null) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    } else {
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

  Future<void> _toggleSavedUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();

    final isSaved = _savedUsers.any((u) => u['id'] == user['id']);

    if (isSaved) {
      _savedUsers.removeWhere((u) => u['id'] == user['id']);
      showCustomSnackBar(
        context,
        message: '${user['username']} removed from your list',
        background: Colors.black87,
        icon: Icons.check_circle_outline,
      );
    } else {
      _savedUsers.add(user);
      showCustomSnackBar(
        context,
        message: '${user['username']} added to your list',
        background: Colors.black87,
        icon: Icons.check_circle_outline,
      );
    }

    await prefs.setString('savedUsers', jsonEncode(_savedUsers));

    setState(() {});
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
              .select('id, username, email')
              .ilike('username', '%$query%');

          setState(
            () => _searchResults = List<Map<String, dynamic>>.from(response),
          );
        }
      } catch (e) {
        print("❌ Error searching users: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  bool _isPickingAvatar = false;
  Future<void> _pickAndUploadAvatar() async {
    if (_isPickingAvatar) return; // جلوگیری از چندبار همزمان
    _isPickingAvatar = true;
    print("🔹 Start picking avatar");
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) {
        print("⚠️ No image picked");
        return;
      }

      print("📸 Image picked: ${pickedFile.path}");

      final user = supabase.auth.currentUser;
      if (user == null) {
        print("❌ No logged-in user");
        return;
      }

      final fileExt = path.extension(pickedFile.path);
      final fileName = "${user.id}$fileExt";
      final filePath = "avatars/$fileName";

      print("📂 Uploading to path: $filePath");

      final uploadResponse = await supabase.storage
          .from('avatars')
          .upload(
            filePath,
            File(pickedFile.path),
            fileOptions: const FileOptions(upsert: true),
          );

      print("✅ Upload response: $uploadResponse");

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(filePath);
      print("🌐 Public URL: $publicUrl");

      final updateResponse = await supabase
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id);

      print("✏️ Profile update response: $updateResponse");

      setState(() {
        user.userMetadata?['avatar_url'] = publicUrl;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile picture updated!")));
        showCustomSnackBar(
        context,
        message: "Profile picture updated!",
        background: Colors.black87,
        icon: Icons.check_circle_outline,
      );
    } catch (e, st) {
      print("❌ Error uploading avatar: $e");
      print("Stack trace: $st");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to update avatar: $e")));
    }
  }
  // Future<void> _playNotificationSound() async {
  //   try {
  //     await _player.setAsset('assets/sounds/notify.mp3'); // مسیر فایل داخل assets
  //     await _player.play();
  //   } catch (e) {
  //     print("❌ Error playing sound: $e");
  //   }
  // }

  Future<void> _openChat(String otherUserId) async {
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

      setState(() {
        _unreadCounts[otherUserId] = 0;
      });

      final messages =
          await supabase
                  .from('messages')
                  .select('id')
                  .eq('room_id', roomId)
                  .neq('sender_id', currentUserId)
              as List<dynamic>;

      final toUpsert = messages
          .map((m) => {'message_id': m['id'], 'user_id': currentUserId})
          .toList();

      if (toUpsert.isNotEmpty) {
        await supabase
            .from('message_reads')
            .upsert(toUpsert, onConflict: 'message_id,user_id');
      }

      // بارگذاری مجدد تعداد واقعی پیام‌های نخونده
      await _loadUnreadCounts();
    } catch (e) {
      print("❌ Failed to open chat: $e");
    }
  }

  Future<void> _loadCurrentUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final profile = await supabase
        .from('profiles')
        .select('username, avatar_url')
        .eq('id', userId)
        .single();

    if (profile != null && mounted) {
      setState(() {
        supabase.auth.currentUser?.userMetadata?['username'] =
            profile['username'];
        supabase.auth.currentUser?.userMetadata?['avatar_url'] =
            profile['avatar_url'];
      });
    }
  }

  @override
  void dispose() {
    // _player.dispose();
    _unreadChannel.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    final combinedUsers = [
      ..._savedUsers, // کاربران ذخیره شده همیشه در بالای لیست
      ..._searchResults.where(
        (u) => !_savedUsers.any((saved) => saved['id'] == u['id']),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("ChatterBox"),
        backgroundColor: const Color.fromARGB(255, 66, 95, 145),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.white),
              accountName: Text(
                user!.userMetadata!['username'] ?? 'User',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              accountEmail: Text(
                user.email ?? '',
                style: const TextStyle(color: Colors.grey),
              ),
              currentAccountPicture: GestureDetector(
                onTap: _pickAndUploadAvatar, // 📌 اینجا متد رو صدا می‌زنیم
                child: CircleAvatar(
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: user.userMetadata?['avatar_url'] != null
                      ? NetworkImage(user.userMetadata!['avatar_url'])
                      : null,
                  child: user.userMetadata?['avatar_url'] == null
                      ? Text(
                          (user.userMetadata?['username'] ?? 'U')[0]
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.black,
                          ),
                        )
                      : null,
                ),
              ),
            ),

            // 📌 گزینه‌های شبیه تلگرام
            ListTile(
              leading: const Icon(Icons.group, color: Colors.blueAccent),
              title: const Text("New Group"),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.blueAccent),
              title: const Text("Contacts"),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.call, color: Colors.blueAccent),
              title: const Text("Calls"),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.bookmark, color: Colors.blueAccent),
              title: const Text("Saved Messages"),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.blueAccent),
              title: const Text("Settings"),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.blueAccent),
              title: const Text("Invite Friends"),
              onTap: () {},
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout"),
              onTap: () async {
                await supabase.auth.signOut();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),

      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background.png"),
            fit: BoxFit.cover, // تصویر تمام صفحه را پوشش می‌دهد
          ),
        ),
        child: Column(
          children: [
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
      ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 150,
                width: 150,
                child: Image.asset(
                  "assets/images/searching_profile.gif", // مسیر GIF
                  fit: BoxFit.contain,
                ),
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
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        )
      : ListView.builder(
          itemCount: combinedUsers.length,
          itemBuilder: (context, index) {
            final u = combinedUsers[index];
            return Card(
              margin: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: Text(
                    (u['username'] ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  u['username'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(u['email'] ?? ""),
                trailing: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.chat,
                      color: Colors.blueAccent,
                      size: 28,
                    ),
                    if ((_unreadCounts[u['id']] ?? 0) > 0)
                      Positioned(
                        right: 4,
                        top: 20,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '${_unreadCounts[u['id']]}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () => _openChat(u['id']),
                onLongPress: () => _toggleSavedUser(u),
              ),
            );
          },
        ),
)

          ],
        ),
      ),
    );
  }
}
