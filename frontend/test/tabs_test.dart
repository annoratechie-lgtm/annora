import 'package:annora/features/assistant/data/assistant_api.dart';
import 'package:annora/features/groceries/presentation/groceries_screen.dart';
import 'package:annora/features/meal_plan/data/meal_plan_api.dart';
import 'package:annora/features/meal_plan/presentation/meal_plan_screen.dart';
import 'package:annora/features/onboarding/data/onboarding_repository.dart';
import 'package:annora/features/profile/data/user_profile_api.dart';
import 'package:annora/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Map<String, dynamic> meal(String date, String type, String name, double kcal) =>
    {
      'meal_date': date,
      'meal_type': type,
      'name': name,
      'source_recipe_code': 'X',
      'nutrition': {
        'servings_unit': 'bowl',
        'unit_serving_energy_kcal': kcal,
        'unit_serving_protein_g': 5,
        'unit_serving_carb_g': 20
      },
    };

final plan = <String, dynamic>{
  'meal_plan': {
    'id': 'plan-1',
    'start_date': '2026-11-17',
    'end_date': '2026-11-23'
  },
  'meals': [
    meal('2026-11-17', 'breakfast', 'Appam', 409),
    meal('2026-11-17', 'lunch', 'Kabuli channa curry', 244),
    meal('2026-11-17', 'lunch', 'Boiled rice (Uble chawal)', 352),
    meal('2026-11-18', 'breakfast', 'Bathua poori', 544),
  ],
};

class FakeApi implements MealPlanApi {
  final calls = <String>[];
  DateTime? generateStart;
  bool failPatch = false;
  int ingredientFetches = 0;
  Map<String, dynamic>? groceryList = {
    'grocery_list': {'id': 'g1'},
    'items': [
      {
        'id': 'i1',
        'ingredient_name': 'Onion',
        'purchase_quantity': 3,
        'unit': 'kg',
        'category': 'Vegetables & herbs',
        'is_purchased': false
      },
      {
        'id': 'i2',
        'ingredient_name': 'Paneer',
        'purchase_quantity': 1.1,
        'unit': 'kg',
        'category': 'Dairy',
        'is_purchased': false
      },
      {
        'id': 'i3',
        'ingredient_name': 'Rice',
        'purchase_quantity': 3,
        'unit': 'kg',
        'category': 'Grains & flours',
        'is_purchased': true
      },
      {
        'id': 'i4',
        'ingredient_name': 'Turmeric',
        'purchase_quantity': 25,
        'unit': 'ml',
        'category': 'Pantry',
        'is_purchased': false
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchMealPlan() async {
    calls.add('fetchMealPlan');
    return plan;
  }

  @override
  Future<Map<String, dynamic>> generateMealPlan({DateTime? startDate}) async {
    calls.add('generateMealPlan');
    generateStart = startDate;
    return {'meal_id': 'plan-2'};
  }

  @override
  Future<Map<String, dynamic>> fetchGroceryList(String id) async {
    calls.add('fetchGroceryList:$id');
    if (groceryList == null)
      throw MealPlanApiException('Not found', statusCode: 404);
    return groceryList!;
  }

  @override
  Future<Map<String, dynamic>> setGroceryItemPurchased(
      String planId, String itemId, bool purchased) async {
    calls.add('setPurchased:$planId:$itemId:$purchased');
    if (failPatch) throw MealPlanApiException('offline');
    return {'id': itemId, 'is_purchased': purchased};
  }

  @override
  Future<Map<String, dynamic>> fetchIngredients(String id) async {
    calls.add('fetchIngredients:$id');
    ingredientFetches++;
    if (ingredientFetches == 1) return {'meals': []}; // not generated yet
    return {
      'meals': [
        {
          'meal_date': '2026-11-17',
          'meal_type': 'lunch',
          'ingredients': [
            {'food_name': 'Onion, big (Allium cepa)', 'display_name': 'Onion'},
            {'food_name': 'Salt', 'display_name': 'Salt'},
            {'food_name': 'Beans, chick peas', 'display_name': 'Kabuli chana'},
          ]
        },
        {
          'meal_date': '2026-11-17',
          'meal_type': 'lunch',
          'ingredients': [
            {'food_name': 'Rice, parboiled, milled', 'display_name': 'Rice'},
            {'food_name': 'Onion, big (Allium cepa)', 'display_name': 'Onion'},
          ]
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> generateIngredients(String id) async {
    calls.add('generateIngredients:$id');
    return {};
  }

  @override
  Future<Map<String, dynamic>> generateGroceryList(String id) async {
    calls.add('generateGroceryList:$id');
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAssistant implements AssistantApi {
  final asked = <String>[];
  @override
  Future<List<ChatMessage>> history() async => [];

  @override
  Future<ChatTurn> send(String message) async {
    asked.add(message);
    return ChatTurn(ChatMessage(id: 'u', isUser: true, text: message),
        ChatMessage(id: 'r', isUser: false, text: 'ok'), const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRepo extends OnboardingRepository {
  Map<String, Object?>? updated;

  @override
  Future<OnboardingProfile?> fetchProfile() async => OnboardingProfile(
        familySize: 4,
        monthlyBudget: 15000,
        dietaryPreference: 'vegetarian',
        dietaryGoals: ['high_protein'],
        onboardingCompleted: true,
      );

  @override
  Future<List<String>> fetchDietaryExclusions() async => ['Peanuts'];

  @override
  Future<void> updateProfile({
    required int familySize,
    required double monthlyBudget,
    required String dietaryPreference,
    required List<String> dietaryGoals,
    required List<String> exclusions,
  }) async {
    updated = {
      'family_size': familySize,
      'monthly_budget': monthlyBudget,
      'dietary_preference': dietaryPreference,
      'dietary_goals': dietaryGoals,
      'exclusions': exclusions,
    };
  }
}

class FakeUserApi implements UserProfileApi {
  final synced = <Map<String, String?>>[];
  @override
  Future<Map<String, dynamic>> fetchProfile() async =>
      {'name': 'Priya Sharma', 'phone': null};
  @override
  Future<Map<String, dynamic>> syncProfile(
      {required String? name, required String? phone}) async {
    synced.add({'name': name, 'phone': phone});
    return {'name': name, 'phone': phone};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1290, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('Groceries', () {
    testWidgets(
        'groups by aisle, separates pantry, and ticks items via the backend',
        (tester) async {
      final api = FakeApi();
      await pump(tester, GroceriesScreen(api: api, repository: FakeRepo()));

      expect(find.text('VEGETABLES & HERBS'), findsOneWidget);
      expect(find.text('DAIRY'), findsOneWidget);
      expect(find.text('1 of 3 bought'), findsOneWidget); // pantry not counted
      expect(find.text('Pantry check'), findsOneWidget);
      expect(find.text('In your basket (1)'), findsOneWidget);

      await tap(tester, find.byKey(const Key('item-i1')));
      expect(api.calls, contains('setPurchased:plan-1:i1:true'));
      expect(find.text('2 of 3 bought'), findsOneWidget);

      await tap(tester, find.text('Turmeric'));
      expect(api.calls, contains('setPurchased:plan-1:i4:true'));
    });

    testWidgets('a failed tick is undone', (tester) async {
      final api = FakeApi()..failPatch = true;
      await pump(tester, GroceriesScreen(api: api, repository: FakeRepo()));
      await tap(tester, find.byKey(const Key('item-i2')));
      expect(find.text('1 of 3 bought'), findsOneWidget);
      expect(find.textContaining("Couldn't save that"), findsOneWidget);
    });

    testWidgets('share copies what is left to buy', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(
          tester, GroceriesScreen(api: FakeApi(), repository: FakeRepo()));
      await tap(tester, find.text('Share list'));
      expect(copied, contains('- Onion: 3 kg'));
      expect(copied, contains('- Paneer: 1.1 kg'));
      expect(copied, isNot(contains('Rice'))); // already bought
      expect(copied, contains('CHECK PANTRY\nTurmeric'));
    });
  });

  group('Plan', () {
    testWidgets(
        'expands a day, loads ingredients on demand and asks the assistant',
        (tester) async {
      final api = FakeApi();
      final assistant = FakeAssistant();
      await pump(
          tester,
          MealPlanScreen(
              api: api,
              assistantApi: assistant,
              repository: FakeRepo(),
              clock: () => DateTime(2026, 11, 17, 10)));

      expect(find.text('Your week'), findsOneWidget);
      expect(find.text('LUNCH'), findsOneWidget); // today is open
      expect(find.text('with Boiled rice (Uble chawal)'), findsOneWidget);

      await tap(tester, find.text('Show ingredients').at(1)); // lunch
      expect(
          api.calls,
          containsAllInOrder([
            'fetchIngredients:plan-1',
            'generateIngredients:plan-1',
            'fetchIngredients:plan-1'
          ]));
      expect(find.text('Kabuli chana'), findsOneWidget);
      expect(find.text('Onion'), findsOneWidget); // de-duplicated
      expect(find.text('Salt'), findsNothing);

      await tap(tester, find.text('Cooking tips').first);
      expect(assistant.asked.single, 'How do I make Appam?');
    });

    testWidgets('making a new plan starts today and rebuilds groceries for it',
        (tester) async {
      final api = FakeApi();
      await pump(
          tester,
          MealPlanScreen(
              api: api,
              repository: FakeRepo(),
              clock: () => DateTime(2026, 11, 19, 10)));
      await tap(tester, find.text('Make a new plan'));
      expect(find.text('This replaces all 7 days of this plan. Continue?'),
          findsOneWidget);
      await tap(tester, find.text('Yes, make a new plan'));
      expect(api.generateStart, DateTime(2026, 11, 19));
      expect(
          api.calls,
          containsAllInOrder([
            'generateMealPlan',
            'generateIngredients:plan-2',
            'generateGroceryList:plan-2'
          ]));
    });
  });

  group('Profile', () {
    testWidgets('edits details, household, notifications and signs out',
        (tester) async {
      final userApi = FakeUserApi();
      final repo = FakeRepo();
      Map<String, dynamic>? savedPrefs;
      var signedOut = false;
      await pump(
        tester,
        ProfileScreen(
          api: userApi,
          repository: repo,
          email: 'priya@example.com',
          readMetadata: () => {},
          saveNotifications: (p) async => savedPrefs = p,
          signOut: () async => signedOut = true,
        ),
      );
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('4 people'), findsOneWidget);
      expect(find.text('₹15,000'), findsOneWidget);

      // Details: bad phone is rejected, good one is sent as +91XXXXXXXXXX.
      await tap(tester, find.text('Add a mobile number'));
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('details-phone')),
              matching: find.byType(TextField)),
          '12345');
      await tap(tester, find.byKey(const Key('details-save')));
      expect(find.textContaining('10-digit Indian mobile'), findsOneWidget);
      expect(userApi.synced, isEmpty);
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('details-phone')),
              matching: find.byType(TextField)),
          '98765 43210');
      await tap(tester, find.byKey(const Key('details-save')));
      expect(userApi.synced.single,
          {'name': 'Priya Sharma', 'phone': '+919876543210'});

      // Household.
      await tap(tester, find.text('Edit').at(1));
      await tap(tester, find.byTooltip('More people'));
      await tap(tester, find.text('Eggetarian'));
      await tap(tester, find.text('₹25k'));
      await tap(tester, find.text('Keto'));
      await tap(tester, find.text('Dairy'));
      await tap(tester, find.byKey(const Key('house-save')));
      expect(repo.updated, {
        'family_size': 5,
        'monthly_budget': 25000.0,
        'dietary_preference': 'eggetarian',
        'dietary_goals': ['keto', 'high_protein'],
        'exclusions': ['Peanuts', 'Dairy'],
      });

      // Notifications (let the "Saved" snackbar go away so it doesn't cover the tap).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('notif-cooking_reminders')));
      expect(savedPrefs, {
        'meal_plan_updates': true,
        'grocery_reminders': true,
        'cooking_reminders': false
      });

      // Sign out with confirmation.
      await tap(tester, find.byKey(const Key('sign-out')));
      expect(signedOut, isFalse);
      // In the app the auth stream swaps this screen for the login page, so the
      // button keeps spinning here; pump a frame instead of waiting to settle.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign out'));
      await tester.pump();
      expect(signedOut, isTrue);
    });
  });

  test('helpers', () {
    expect(normalizeIndianMobile(''), isNull);
    expect(normalizeIndianMobile('+91 98765 43210'), '+919876543210');
    expect(() => normalizeIndianMobile('12345'), throwsFormatException);
    expect(
        groupIngredients({
          'meals': [
            {
              'meal_date': '2026-11-17T00:00:00',
              'meal_type': 'Dinner',
              'ingredients': [
                {'display_name': 'Paneer'},
                {'display_name': 'Salt'}
              ]
            },
          ]
        }),
        {
          '2026-11-17|dinner': ['Paneer']
        });
    expect(shareText(const [], 'Heading'), 'Heading');
  });
}
