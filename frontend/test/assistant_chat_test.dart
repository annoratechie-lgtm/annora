import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:annora/features/assistant/data/assistant_api.dart';
import 'package:annora/features/assistant/presentation/assistant_chat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  testWidgets('Assist tab explains scope and requires sign-in to send', (
    tester,
  ) async {
    final api = AssistantApi(baseUrl: 'http://localhost:8000');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AssistantChat(api: api)),
      ),
    );

    expect(find.text('⚡ Annora Assist'), findsOneWidget);
    expect(find.textContaining('cannot access other users'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'What is in my meal plan?');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Please sign in to use Annora Assist.'),
      findsOneWidget,
    );
  });
}
