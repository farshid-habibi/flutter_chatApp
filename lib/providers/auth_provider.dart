import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/supabase_client.dart';
import '../data/auth_service.dart';
import '../domain/user_model.dart';

class AuthProvider with ChangeNotifier {
  final _authService = AuthService();
  UserModel? currentUser;
  bool isLoading = false;

  Future<String?> signUp(String email, String password, {String? name}) async {
    isLoading = true;
    notifyListeners();

    try {
      final response = await _authService.signUp(email, password);

      if (response.user != null) {
        final userId = response.user!.id;


        final insertRes = await supabase.from('register').insert({
          'id': userId,
          'email': email,
          'name': name ?? '',
          'password': password,
        }).select();
        currentUser = UserModel(id: userId, email: email);
        return null;
      } else {
        return "ثبت‌نام انجام نشد!";
      }
    } catch (e) {
   
      return e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    isLoading = true;
    notifyListeners();

    try {
      final response = await _authService.signIn(email, password);
      if (response.user != null) {
        currentUser = UserModel(
          id: response.user!.id,
          email: response.user!.email ?? '',
        );
      }
    } catch (e) {
   
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    currentUser = null;
    notifyListeners();
  }
}
