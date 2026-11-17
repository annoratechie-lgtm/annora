import 'package:annora/features/onboarding/data/onboarding_repository.dart';
import 'package:annora/features/onboarding/presentation/onboarding_screen.dart';
import 'package:annora/features/onboarding/state/onboarding_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeRepository extends OnboardingRepository {
  Map<String, Object?>? saved;
  bool fail = false;

  @override
  Future<void> saveOnboarding({
    required int familySize,
    required double monthlyBudget,
    required String dietaryPreference,
    required List<String> dietaryGoals,
    required List<String> exclusions,
  }) async {
    if (fail) throw Exception('network down');
    saved = {
      'family_size': familySize,
      'monthly_budget': monthlyBudget,
      'dietary_preference': dietaryPreference,
      'dietary_goals': dietaryGoals,
      'exclusions': cleanExclusions(exclusions),
    };
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late _FakeRepository repo;
  String? savedName;
  String? savedPhone;
  late bool completed;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    repo = _FakeRepository();
    savedName = null;
    savedPhone = null;
    completed = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [onboardingRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: OnboardingScreen(
          initialName: 'Priya Sharma',
          saveProfile: ({required String name, String? phone}) async {
            savedName = name;
            savedPhone = phone;
          },
          onCompleted: () => completed = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.descendant(
      of: find.byKey(Key(key)), matching: find.byType(TextField));

  ElevatedButton submitButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byKey(const Key('onboarding-submit')));

  testWidgets('saves every answer from the single page', (tester) async {
    await pumpScreen(tester);

    // Name is pre-filled; diet and budget are still required.
    expect(find.text('From Google'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    expect(find.text('Choose a diet & a budget to continue'), findsOneWidget);

    await tester.enterText(field('onboarding-phone'), '9876543210');
    await tap(tester, find.byTooltip('More people')); // 4 -> 5
    await tap(tester, find.text('Vegetarian'));
    expect(find.text('Choose a budget to continue'), findsOneWidget);
    await tap(tester, find.text('₹15k'));
    await tap(tester, find.text('High protein'));
    await tap(tester, find.text('Peanuts'));

    // Custom exclusion, then a duplicate of a preset (should just select it).
    await tester.enterText(field('onboarding-extra'), '  brinjal ');
    await tester.pump();
    await tap(tester, find.byKey(const Key('onboarding-extra-add')));
    await tester.enterText(field('onboarding-extra'), 'dairy');
    await tester.pump();
    await tap(tester, find.byKey(const Key('onboarding-extra-add')));
    expect(find.text('brinjal'), findsOneWidget);

    expect(submitButton(tester).onPressed, isNotNull);
    await tap(tester, find.byKey(const Key('onboarding-submit')));

    expect(savedName, 'Priya Sharma');
    expect(savedPhone, '+919876543210');
    expect(repo.saved, {
      'family_size': 5,
      'monthly_budget': 15000.0,
      'dietary_preference': 'vegetarian',
      'dietary_goals': ['high_protein'],
      'exclusions': ['Peanuts', 'Dairy', 'brinjal'],
    });

    expect(find.text('Your kitchen is ready, Priya!'), findsOneWidget);
    await tap(tester, find.byKey(const Key('onboarding-done')));
    expect(completed, isTrue);
  });

  testWidgets(
      'exact amount overrides presets; bad phone blocks saving; no goals saves empty list',
      (tester) async {
    await pumpScreen(tester);

    await tap(tester, find.text('Non-vegetarian'));
    await tap(tester, find.text('₹10k'));
    await tester.enterText(field('onboarding-amount'), '012000');
    await tester.pump();
    expect(find.text('12,000'), findsOneWidget);

    await tester.enterText(field('onboarding-phone'), '12345');
    await tester.pump();
    expect(find.text('Fix your mobile number to continue'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);

    await tester.enterText(field('onboarding-phone'), '');
    await tester.pump();
    await tap(tester, find.byKey(const Key('onboarding-submit')));

    expect(savedPhone, isNull);
    expect(repo.saved, {
      'family_size': 4,
      'monthly_budget': 12000.0,
      'dietary_preference': 'non_vegetarian',
      'dietary_goals': <String>[],
      'exclusions': <String>[],
    });
  });

  testWidgets('a failed save keeps the user on the page with a retryable error',
      (tester) async {
    await pumpScreen(tester);
    repo.fail = true;

    await tap(tester, find.text('Vegan'));
    await tap(tester, find.text('₹5k'));
    await tap(tester, find.byKey(const Key('onboarding-submit')));

    expect(
        find.text(
            "Couldn't save your answers. Check your connection and try again."),
        findsOneWidget);
    expect(find.text('Your kitchen is ready, Priya!'), findsNothing);
    expect(submitButton(tester).onPressed, isNotNull); // can retry
    expect(completed, isFalse);
  });

  test('formatIndian uses Indian digit grouping', () {
    expect(formatIndian(950), '950');
    expect(formatIndian(12000), '12,000');
    expect(formatIndian(150000), '1,50,000');
    expect(formatIndian(1234567), '12,34,567');
  });
}
