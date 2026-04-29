import 'package:flutter/foundation.dart';

import 'app_user_profile.dart';

class AuthSession extends ChangeNotifier {
  AppUserProfile? _user;
  bool _isLoading = true;

  AppUserProfile? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isUser => _user?.isUser ?? false;

  void setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  void setUser(AppUserProfile? user) {
    _user = user;
    _isLoading = false;
    notifyListeners();
  }
}
