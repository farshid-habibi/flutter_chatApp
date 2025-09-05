import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/Screens/Chat/chat_page.dart';
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
      setState(() {}); // بروز رسانی UI
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user['username']} added to your list')),
      );
    }
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

          setState(() =>
              _searchResults = List<Map<String, dynamic>>.from(response));
        }
      } catch (e) {
        print("❌ Error searching users: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
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
          (u) => !_savedUsers.any((saved) => saved['id'] == u['id']))
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("ChatterBox"),
        backgroundColor: Colors.blueAccent,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(user!.userMetadata!['username'] ?? 'User'),
              accountEmail: Text(user.email ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  (user.userMetadata!['username'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(fontSize: 24, color: Colors.black),
                ),
              ),
              decoration: const BoxDecoration(color: Colors.blueAccent),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.blueAccent),
              title: const Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
                            horizontal: 12, vertical: 6),
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
                          trailing: const Icon(Icons.chat,
                              color: Colors.blueAccent),
                          onTap: () => _openChat(u['id']),
                          onLongPress: () => _saveUser(u), // ذخیره با نگه داشتن
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
