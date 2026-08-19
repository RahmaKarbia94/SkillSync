import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AuthStatus { unauthenticated, authenticated, loading }

enum UserRole {
  admin,
  recruiter,
  evaluator,
  candidate,
  unknown;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.unknown,
    );
  }
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.token,
    this.role = UserRole.unknown,
    this.errorMessage,
  });

  final AuthStatus status;
  final String? token;
  final UserRole role;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && token != null;

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    UserRole? role,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      role: role ?? this.role,
      errorMessage: errorMessage,
    );
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main.dart');
});

const _tokenKey = 'jwt_token';
const _roleKey = 'user_role';
const _apiBaseUrl = 'http://localhost:8080/api/v1';

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final storedToken = prefs.getString(_tokenKey);
    final storedRole = prefs.getString(_roleKey);

    if (storedToken != null && storedRole != null) {
      return AuthState(
        status: AuthStatus.authenticated,
        token: storedToken,
        role: UserRole.fromString(storedRole),
      );
    }
    return const AuthState();
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        final roleString = (data['user'] as Map<String, dynamic>)['role'] as String;
        final role = UserRole.fromString(roleString);

        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.setString(_tokenKey, token);
        await prefs.setString(_roleKey, role.name);

        state = AuthState(status: AuthStatus.authenticated, token: token, role: role);
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        state = AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: data['error'] as String? ?? 'Login failed',
        );
      }
    } catch (_) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Unable to reach server. Please try again.',
      );
    }
  }

  Future<void> logout() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);