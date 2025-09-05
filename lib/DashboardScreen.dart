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

  List<Map<String, dynamic>> _foundUsers = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedUsers();
  }

  Future<void> _loadSavedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('foundUsers');
    if (saved != null) {
      setState(() {
        _foundUsers = List<Map<String, dynamic>>.from(jsonDecode(saved));
      });
    }
  }

  Future<void> _saveUsers() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('foundUsers', jsonEncode(_foundUsers));
  }

  Future<void> _searchUser(String username) async {
    try {
      final response = await supabase
          .from('profiles')
          .select('id, username, email')
          .eq('username', username)
          .maybeSingle();

      if (response != null) {
        final userMap = {
          'id': response['id'],
          'username': response['username'],
          'email': response['email'],
        };

        if (!_foundUsers.any((u) => u['id'] == userMap['id'])) {
          setState(() {
            _foundUsers.add(userMap);
          });
          _saveUsers();
        }
      } else {
        setState(() => _error = 'User not found');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
      print("❌ Error searching user: $e");
    }
  }

  void _showSearchDialog() {
    final TextEditingController _controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search User'),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Enter username',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _searchUser(_controller.text.trim());
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

Future<String> _getOrCreateRoom(String otherUserId) async {
  final currentUserId = supabase.auth.currentUser!.id;
  print("📌 Current User ID: $currentUserId, Other User ID: $otherUserId");

  try {
    // بررسی وجود روم
    final existingRoom = await supabase
        .from('rooms')
        .select('id')
        .or(
          'name.eq.private_${currentUserId}_$otherUserId,name.eq.private_${otherUserId}_$currentUserId'
        )
        .maybeSingle();

    if (existingRoom != null) {
      print("ℹ️ Existing room found: ${existingRoom['id']}");
      return existingRoom['id'];
    }

    // ایجاد روم جدید
    final newRoom = await supabase
        .from('rooms')
        .insert({
          'name': 'private_${currentUserId}_$otherUserId',
          'creator_id': currentUserId,
        })
        .select()
        .single();

    final roomId = newRoom['id'];
    print("✅ New room created: $roomId");

    // اضافه کردن اعضا به room_members
    print("🔹 Inserting members into room_members...");
    final insertedMembers = await supabase.from('room_members').insert([
      {'room_id': roomId, 'user_id': currentUserId},
      {'room_id': roomId, 'user_id': otherUserId},
    ]).select();

    print("🔹 insertedMembers response: $insertedMembers");

    if (insertedMembers == null || (insertedMembers as List).isEmpty) {
      print("❌ Failed to add members. Deleting room...");
      await supabase.from('rooms').delete().eq('id', roomId);
      throw Exception('Failed to add members to room');
    }

    print("✅ Members successfully added to room: $roomId");
    return roomId;
  } catch (e, stack) {
    print("❌ Error in _getOrCreateRoom: $e");
    print(stack);
    rethrow;
  }
}


  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const WelcomeScreen(),
                ),
                (route) => false,
              );
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Welcome, ${user?.email ?? 'User'}",
              style: const TextStyle(fontSize: 18),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const Divider(),
          Expanded(
            child: _foundUsers.isEmpty
                ? const Center(child: Text("No users found. Search to add users."))
                : ListView.builder(
                    itemCount: _foundUsers.length,
                    itemBuilder: (context, index) {
                      final u = _foundUsers[index];
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(u['username'] ?? 'No username'),
                        subtitle: Text(u['email'] ?? 'No email'),
                        onTap: () async {
                          try {
                            final roomId = await _getOrCreateRoom(u['id']);
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatPage(roomId: roomId),
                              ),
                            );
                          } catch (e) {
                            print("❌ Failed to open chat: $e");
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSearchDialog,
        child: const Icon(Icons.search),
        tooltip: 'Search User by Username',
      ),
    );
  }
}
