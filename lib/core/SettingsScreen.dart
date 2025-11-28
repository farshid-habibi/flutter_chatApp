import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final userId = supabase.auth.currentUser!.id;

    final profile = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();

    _usernameController.text = profile['username'] ?? "";
    _descriptionController.text = profile['description'] ?? "";
    avatarUrl = profile['avatar_url'] ?? "";

    setState(() {});
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _loading = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final ext = path.extension(picked.path);
      final fileName = "$userId$ext";
      final filePath = "avatars/$fileName";

      await supabase.storage
          .from('avatars')
          .upload(
            filePath,
            File(picked.path),
            fileOptions: const FileOptions(upsert: true),
          );

      final url = supabase.storage.from('avatars').getPublicUrl(filePath);

      await supabase
          .from('profiles')
          .update({'avatar_url': url})
          .eq('id', userId);

      setState(() => avatarUrl = url);
    } catch (e) {
      print("❌ Avatar upload failed: $e");
    }

    setState(() => _loading = false);
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = supabase.auth.currentUser!.id;

    setState(() => _loading = true);

    try {
      await supabase
          .from('profiles')
          .update({
            'username': _usernameController.text.trim(),
            'description': _descriptionController.text.trim(),
          })
          .eq('id', userId);

      Navigator.pop(context, true); // برمیگردیم و به داشبورد می‌گوییم reload کن
    } catch (e) {
      print("❌ Error updating profile: $e");
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white70,
            size: 18,
          ),
          splashRadius: 22,
        ),
        title: const Text(
          "Profile Settings",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A0F2C),
                  Color(0xFF101B42),
                  Color(0xFF0E1735),
                ],
              ),
            ),
          ),
          // Positioned.fill(
          //   child: Opacity(
          //     opacity: 0.07,
          //     child: Image.asset("assets/particles.png", fit: BoxFit.cover),
          //   ),
          // ),
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 120,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        TweenAnimationBuilder(
                          tween: Tween<double>(begin: 0.8, end: 1),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) {
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: GestureDetector(
                            onTap: _pickAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueAccent.withOpacity(0.6),
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 65,
                                backgroundImage:
                                    avatarUrl != null && avatarUrl!.isNotEmpty
                                    ? NetworkImage(avatarUrl!)
                                    : null,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                child: avatarUrl == null || avatarUrl!.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 60,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: const EdgeInsets.all(25),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                ),
                              ),
                              child: Column(
                                children: [
                                  _modernInput(
                                    controller: _usernameController,
                                    label: "Username",
                                    icon: Icons.person_outline,
                                    minLength: 6,
                                    maxLength: 15,
                                  ),
                                  const SizedBox(height: 20),
                                  _modernInput(
                                    controller: _descriptionController,
                                    label: "About You",
                                    icon: Icons.edit,
                                    maxLength: 30,
                                  ),
                                  const SizedBox(height: 35),
                                  GestureDetector(
                                    onTap: _saveChanges,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 60,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF4A9CFF),
                                            Color(0xFF6C6CFF),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blueAccent
                                                .withOpacity(0.4),
                                            blurRadius: 20,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: const Text(
                                        "Save Changes",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _modernInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int? minLength,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLength: maxLength,
          validator: (value) {
            if (value == null || value.isEmpty) return '$label is required';
            if (minLength != null && value.length < minLength) {
              return '$label must be at least $minLength characters';
            }
            if (maxLength != null && value.length > maxLength) {
              return '$label cannot exceed $maxLength characters';
            }
            return null;
          },
          decoration: InputDecoration(
            counterText: "",
            filled: true,
            // فقط کمی شفافیت کمتر، تا کادر مشخص شود
            fillColor: Colors.white.withOpacity(0.12),
            prefixIcon: Icon(icon, color: Colors.white70),
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(18),
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 10,
            ),
          ),
        ),
      ],
    );
  }
}
