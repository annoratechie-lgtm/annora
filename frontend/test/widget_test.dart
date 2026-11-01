import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:annora/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Supabase persists the auth session via shared_preferences internally.
    // There's no real platform under `flutter test`, so seed an in-memory
    // mock before initialize() runs, or it throws MissingPluginException.
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(
      fileInput: 'SUPABASE_URL=https://example.supabase.co\n'
          'SUPABASE_PUBLISHABLE_KEY=test-anon-key\n'
          'ANNORA_BACKEND_URL=http://localhost:8000\n',
    );
    await Supabase.initialize(
        url: 'https://example.supabase.co', anonKey: 'test-anon-key');
  });

  testWidgets('App boots and shows Annora title', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AnnoraApp()));
    expect(find.text('Annora'), findsOneWidget);
  });
}
