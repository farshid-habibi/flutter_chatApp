import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/Screens/Chat/chat_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/Screens/Welcome/welcome_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _checkAndRefreshSession();
    _loadSavedUsers();
    _loadCurrentUserProfile();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user['username']} added to your list')),
      );
    }
  }

  Future<void> _toggleSavedUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();

    final isSaved = _savedUsers.any((u) => u['id'] == user['id']);

    if (isSaved) {
      _savedUsers.removeWhere((u) => u['id'] == user['id']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user['username']} removed from your list')),
      );
    } else {
      _savedUsers.add(user);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user['username']} added to your list')),
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
    } catch (e, st) {
      print("❌ Error uploading avatar: $e");
      print("Stack trace: $st");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to update avatar: $e")));
    }
  }

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
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatPage(roomId: roomId)),
      );
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
        backgroundColor: Colors.blueAccent,
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

      body: Column(
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
                ? const Center(
                    child: Text(
                      "No users found.",
                      style: TextStyle(fontSize: 16),
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
                          subtitle: Text(u['email'] ?? ''),
                          trailing: const Icon(
                            Icons.chat,
                            color: Colors.blueAccent,
                          ),
                          onTap: () => _openChat(u['id']),
                          onLongPress: () =>
                              _toggleSavedUser(u), 
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
