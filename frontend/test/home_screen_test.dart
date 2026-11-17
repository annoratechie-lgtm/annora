import 'package:annora/features/assistant/data/assistant_api.dart';
import 'package:annora/features/groceries/presentation/groceries_screen.dart';
import 'package:annora/features/home/presentation/home_screen.dart';
import 'package:annora/features/meal_plan/data/meal_plan_api.dart';
import 'package:annora/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Records every backend call the screens make.
class FakeMealPlanApi implements MealPlanApi {
  Map<String, dynamic>? plan; // null -> 404 (no plan)
  Map<String, dynamic>? groceryList; // null -> 404 (no list)
  final calls = <String>[];
  DateTime? generateStart;

  @override
  Future<Map<String, dynamic>> fetchMealPlan() async {
    calls.add('fetchMealPlan');
    if (plan == null) throw MealPlanApiException('Not found', statusCode: 404);
    return plan!;
  }

  @override
  Future<Map<String, dynamic>> generateMealPlan({DateTime? startDate}) async {
    calls.add('generateMealPlan');
    generateStart = startDate;
    return {'status': 'active'};
  }

  @override
  Future<Map<String, dynamic>> fetchGroceryList(String mealPlanId) async {
    calls.add('fetchGroceryList:$mealPlanId');
    if (groceryList == null)
      throw MealPlanApiException('Not found', statusCode: 404);
    return groceryList!;
  }

  @override
  Future<Map<String, dynamic>> generateIngredients(String mealPlanId) async {
    calls.add('generateIngredients:$mealPlanId');
    return {'ingredients': []};
  }

  @override
  Future<Map<String, dynamic>> generateGroceryList(String mealPlanId) async {
    calls.add('generateGroceryList:$mealPlanId');
    groceryList = {
      'grocery_list': {'id': 'g1'},
      'items': [
        {
          'ingredient_name': 'Rice',
          'purchase_quantity': 2,
          'unit': 'kg',
          'category': 'grains',
          'is_purchased': false,
          'is_urgent': false
        },
      ],
    };
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAssistantApi implements AssistantApi {
  final asked = <String>[];

  @override
  Future<String> ask(String message) async {
    asked.add(message);
    return 'Here is how.';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRepository extends OnboardingRepository {
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
}

Map<String, dynamic> meal(
        String date, String type, String name, double kcal, double p, double c,
        [String unit = 'bowl']) =>
    {
      'meal_date': date,
      'meal_type': type,
      'name': name,
      'source_recipe_code': 'X',
      'nutrition': {
        'servings_unit': unit,
        'unit_serving_energy_kcal': kcal,
        'unit_serving_protein_g': p,
        'unit_serving_carb_g': c,
      },
    };

final samplePlan = <String, dynamic>{
  'meal_plan': {
    'id': 'plan-1',
    'start_date': '2026-11-17',
    'end_date': '2026-11-23'
  },
  'meals': [
    meal('2026-11-17', 'breakfast', 'Appam', 409, 4.8, 20.3, 'appam'),
    meal('2026-11-17', 'lunch', 'Kabuli channa curry', 244, 10.4, 27.1),
    meal('2026-11-17', 'lunch', 'Boiled rice (Uble chawal)', 352, 7.8, 77.2,
        'plate'),
    meal('2026-11-17', 'dinner', 'Kadhai Paneer', 344, 13.8, 23.4),
    meal('2026-11-18', 'breakfast', 'Bathua poori', 544, 2.1, 12.6, 'poori'),
    meal('2026-11-18', 'lunch', 'Paneer pulao', 4876, 16.6, 73.4,
        'plate'), // implausible kcal
  ],
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeMealPlanApi api;
  late FakeAssistantApi assistant;

  Future<void> pumpHome(WidgetTester tester, {required DateTime now}) async {
    tester.view.physicalSize = const Size(1290, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        mealPlanApi: api,
        assistantApi: assistant,
        repository: FakeRepository(),
        clock: () => now,
        displayName: 'Priya',
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  setUp(() {
    api = FakeMealPlanApi();
    assistant = FakeAssistantApi();
  });

  testWidgets("shows today's menu from the plan and switches days",
      (tester) async {
    api.plan = samplePlan;
    await pumpHome(tester, now: DateTime(2026, 11, 17, 14));

    expect(find.text('Good afternoon, Priya'), findsOneWidget);
    expect(find.text("TODAY'S MENU"), findsOneWidget);
    expect(find.text('Appam'), findsOneWidget);
    expect(find.text('Kabuli channa curry'), findsOneWidget);
    expect(find.text('with Boiled rice (Uble chawal)'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Planning for'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Planning for'), findsOneWidget);
    expect(api.calls, ['fetchMealPlan', 'fetchGroceryList:plan-1']);
    await tester.scrollUntilVisible(
        find.byKey(const Key('day-2026-11-18')), -300,
        scrollable: find.byType(Scrollable).first);

    await tap(tester, find.byKey(const Key('day-2026-11-18')));
    expect(find.text("WEDNESDAY'S MENU"), findsOneWidget);
    expect(find.text('Bathua poori'), findsOneWidget);
    // Implausible calories are flagged and left out of the day total.
    expect(find.text('Calories unverified'), findsOneWidget);
    expect(find.textContaining('1 dish left out of calories'), findsOneWidget);
  });

  testWidgets('no plan: "Plan my week" generates starting today',
      (tester) async {
    await pumpHome(tester, now: DateTime(2026, 11, 17, 9));
    expect(find.text("Let's plan your week"), findsOneWidget);
    expect(find.textContaining('Nothing with Peanuts'), findsOneWidget);

    await tap(tester, find.byKey(const Key('plan-my-week')));
    expect(api.calls, contains('generateMealPlan'));
    expect(api.generateStart, DateTime(2026, 11, 17));
  });

  testWidgets('plan ending tomorrow: next plan starts the day after it ends',
      (tester) async {
    api.plan = samplePlan;
    await pumpHome(tester, now: DateTime(2026, 11, 22, 19));
    expect(find.text('Your plan ends tomorrow'), findsOneWidget);

    await tap(tester, find.byKey(const Key('plan-next-week')));
    expect(api.generateStart, DateTime(2026, 11, 24));
  });

  testWidgets(
      'make grocery list saves ingredients first, then the list, for this plan',
      (tester) async {
    api.plan = samplePlan;
    await pumpHome(tester, now: DateTime(2026, 11, 17, 14));
    expect(find.text('No grocery list yet'), findsOneWidget);

    api.calls.clear();
    await tap(tester, find.byKey(const Key('make-grocery-list')));
    expect(api.calls.take(2),
        ['generateIngredients:plan-1', 'generateGroceryList:plan-1']);
    expect(find.text("This week's groceries"), findsOneWidget);
    expect(find.text('1 items'), findsOneWidget);
  });

  testWidgets('cooking tips and the ask box send the question to the assistant',
      (tester) async {
    api.plan = samplePlan;
    await pumpHome(tester, now: DateTime(2026, 11, 17, 14));

    await tap(tester, find.text('Cooking tips').first);
    expect(assistant.asked, ['How do I make Appam?']);
    Navigator.of(tester.element(find.byType(HomeScreen))).pop();
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('ask-field')), 'What goes with paneer?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(assistant.asked.last, 'What goes with paneer?');
  });

  testWidgets('groceries screen groups items and builds a missing list',
      (tester) async {
    api.plan = samplePlan;
    tester.view.physicalSize = const Size(1290, 2800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: GroceriesScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('No grocery list yet'), findsOneWidget);

    await tap(tester, find.text('Make grocery list'));
    expect(
        api.calls,
        containsAllInOrder(
            ['generateIngredients:plan-1', 'generateGroceryList:plan-1']));
    expect(
        find.text('GRAINS'), findsOneWidget); // unknown categories still show
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('2 kg'), findsOneWidget);
  });

  test('formatQuantity trims decimals', () {
    expect(formatQuantity(2, 'kg'), '2 kg');
    expect(formatQuantity(1.5, 'kg'), '1.5 kg');
    expect(formatQuantity(0.25, ''), '0.25');
  });
}
