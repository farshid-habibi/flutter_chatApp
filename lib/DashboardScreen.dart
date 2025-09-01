import 'dart:convert';
import 'package:flutter/material.dart';
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

  List<Map<String, dynamic>> _foundUsers = []; // List of found users
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedUsers(); // Load saved users
  }

  // Load saved list from SharedPreferences
  Future<void> _loadSavedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('foundUsers');
    if (saved != null) {
      setState(() {
        _foundUsers = List<Map<String, dynamic>>.from(jsonDecode(saved));
      });
    }
  }

  // Save list to SharedPreferences
  Future<void> _saveUsers() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('foundUsers', jsonEncode(_foundUsers));
  }

  // Search user by username and add to the list
  Future<void> _searchUser(String username) async {
    if (username.trim().isEmpty) {
      setState(() {
        _error = 'Please enter a username';
      });
      return;
    }

    try {
      final response = await supabase
          .from('profiles')
          .select('id, username, email') // Only id, username, email
          .eq('username', username)
          .maybeSingle();

      setState(() {
        if (response == null) {
          _error = 'User not found';
        } else {
          _error = null;
          final userMap = {
            'id': response['id'],
            'username': response['username'],
            'email': response['email'],
          };

          // Add to list only if not already added
          if (!_foundUsers.any((u) => u['id'] == userMap['id'])) {
            _foundUsers.add(userMap);
            _saveUsers(); // Save permanently
          }
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    }
  }

  // Show dialog to enter username
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
          // Display current user
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Welcome, ${user?.email ?? 'User'}",
              style: const TextStyle(fontSize: 18),
            ),
          ),
          // Display error message
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const Divider(),
          // Display list of found users
          Expanded(
            child: _foundUsers.isEmpty
                ? const Center(
                    child: Text("No users found. Search to add users."),
                  )
                : ListView.builder(
                    itemCount: _foundUsers.length,
                    itemBuilder: (context, index) {
                      final u = _foundUsers[index];
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(u['username'] ?? 'No username'),
                        subtitle: Text(u['email'] ?? 'No email'),
                        // trailing: Text(u['id'] ?? ''),
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
