import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth calls. Screens talk to this, never to
/// Supabase.instance.client directly -- keeps auth logic in one
/// swappable place.
// class AuthRepository {
//   final SupabaseClient _client = Supabase.instance.client;

//   Future<void> signInWithGoogle() {
//     return _client.auth.signInWithOAuth(
//       OAuthProvider.google,
//       redirectTo: 'io.supabase.annora://login-callback',
//     );
//   }

//   Session? get currentSession => _client.auth.currentSession;

//   Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
// }

class AuthRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      // On web, null lets Supabase redirect back to the current page's
      // origin automatically. The custom scheme only makes sense on
      // Android/iOS, where there's a real deep link to catch.
      redirectTo: kIsWeb ? null : 'io.supabase.annora://login-callback',
    );
  }

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}