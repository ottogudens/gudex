import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

const _storage = FlutterSecureStorage();

/// Represents the current authentication session.
@immutable
class AuthState {
  const AuthState({
    this.token,
    this.role,
    this.name,
    this.isLoading = true,
    this.accessToken,
    this.isPasswordReset = false,
  });

  final String? token;
  final String? role;
  final String? name;
  final bool isLoading;

  /// Deep-link invite / password-reset token from URL params.
  final String? accessToken;
  final bool isPasswordReset;

  bool get isAuthenticated => token != null && role != null;

  AuthState copyWith({
    String? token,
    String? role,
    String? name,
    bool? isLoading,
    String? accessToken,
    bool? isPasswordReset,
  }) =>
      AuthState(
        token: token ?? this.token,
        role: role ?? this.role,
        name: name ?? this.name,
        isLoading: isLoading ?? this.isLoading,
        accessToken: accessToken ?? this.accessToken,
        isPasswordReset: isPasswordReset ?? this.isPasswordReset,
      );
}

/// Manages authentication state.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Kick off async restore; starts in loading state.
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    final token = await _storage.read(key: 'access_token');
    final role = await _storage.read(key: 'role');
    final name = await _storage.read(key: 'full_name');
    state = AuthState(
      token: token,
      role: role,
      name: name,
      isLoading: false,
      accessToken: state.accessToken,
      isPasswordReset: state.isPasswordReset,
    );
  }

  /// Call after a successful login to persist the session.
  Future<void> signIn(Map<String, dynamic> session) async {
    final token = session['access_token'] as String;
    final role = session['role'] as String;
    final name = session['full_name'] as String;
    await _storage.write(key: 'access_token', value: token);
    await _storage.write(key: 'role', value: role);
    await _storage.write(key: 'full_name', value: name);
    state = AuthState(token: token, role: role, name: name, isLoading: false);
  }

  /// Sign out, clearing all stored credentials except theme preference.
  Future<void> signOut() async {
    final themePreference = await _storage.read(key: 'theme_mode');
    await _storage.deleteAll();
    if (themePreference != null) {
      await _storage.write(key: 'theme_mode', value: themePreference);
    }
    state = const AuthState(isLoading: false);
  }

  /// Attempt to log in with email/password credentials.
  Future<void> login(String email, String password) async {
    final api = ApiClient(apiBaseUrl);
    final session = await api.login(email, password);
    await signIn(session);
  }

  /// Set deep-link parameters (invite / reset) from URL query params.
  void setDeepLinkParams({String? accessToken, bool isPasswordReset = false}) {
    state = state.copyWith(
      accessToken: accessToken,
      isPasswordReset: isPasswordReset,
    );
  }
}

/// The global auth provider.
final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Provides a pre-configured [ApiClient] using the current session token.
final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authProvider);
  return ApiClient(apiBaseUrl, token: auth.token);
});

/// Theme mode notifier backed by secure storage.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

/// Initialize theme mode from storage. Call once at app start.
Future<ThemeMode> loadThemeMode() async {
  final value = await _storage.read(key: 'theme_mode');
  return value == 'dark' ? ThemeMode.dark : ThemeMode.light;
}

/// Persist theme mode change.
Future<void> saveThemeMode(ThemeMode mode) async {
  await _storage.write(key: 'theme_mode', value: mode == ThemeMode.dark ? 'dark' : 'light');
}
