import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:annora/features/assistant/data/assistant_api.dart';
import 'package:annora/features/assistant/presentation/assistant_chat.dart';
import 'package:annora/features/meal_plan/data/meal_plan_api.dart';
import 'package:annora/features/meal_plan/data/plan_models.dart';
import 'package:annora/features/meal_plan/presentation/swap_sheet.dart';
import 'package:annora/features/profile/presentation/memory_card.dart';

const swapAction = AssistantAction(
  type: 'swap',
  summary: 'More protein on Thursday',
  swaps: [
    ProposedSwap(
        date: '2026-11-19',
        mealType: 'dinner',
        fromName: 'Aloo gobhi',
        toName: 'Palak paneer'),
  ],
);

class FakeAssistant implements AssistantApi {
  List<ChatMessage> saved = [];
  final sent = <String>[];
  final applied = <String>[];
  final dismissed = <String>[];
  bool cleared = false;
  AssistantApiException? applyError;
  List<MemoryFact> facts = [];

  @override
  Future<List<ChatMessage>> history() async => saved;

  @override
  Future<ChatTurn> send(String message) async {
    sent.add(message);
    return ChatTurn(
      ChatMessage(id: 'u${sent.length}', isUser: true, text: message),
      ChatMessage(
          id: 'r${sent.length}',
          isUser: false,
          text: '**Palak paneer** has more protein. Tap Apply to update your plan.',
          action: swapAction,
          actionStatus: 'proposed'),
      const ["Doesn't like bhindi"],
    );
  }

  @override
  Future<ApplyResult> apply(String messageId) async {
    if (applyError != null) throw applyError!;
    applied.add(messageId);
    return ApplyResult(
      ChatMessage(
          id: messageId,
          isUser: false,
          text: 'x',
          action: swapAction,
          actionStatus: 'applied'),
      ChatMessage(
          id: 'c1',
          isUser: false,
          text: 'Done! Your plan is updated:\n- Thursday dinner: Palak paneer (was Aloo gobhi)'),
    );
  }

  @override
  Future<ChatMessage> dismiss(String messageId) async {
    dismissed.add(messageId);
    return ChatMessage(
        id: messageId,
        isUser: false,
        text: 'x',
        action: swapAction,
        actionStatus: 'dismissed');
  }

  @override
  Future<void> clearChat() async => cleared = true;

  @override
  Future<List<MemoryFact>> memory() async => facts;

  @override
  Future<MemoryFact> addMemory(String fact, {String kind = 'preference'}) async {
    final f = MemoryFact(id: 'm${facts.length + 1}', fact: fact, kind: kind);
    facts = [...facts, f];
    return f;
  }

  @override
  Future<MemoryFact> updateMemory(String id, String fact) async =>
      MemoryFact(id: id, fact: fact, kind: 'preference');

  @override
  Future<void> deleteMemory(String id) async =>
      facts = facts.where((f) => f.id != id).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMealPlanApi implements MealPlanApi {
  final swaps = <String>[];

  @override
  Future<Map<String, dynamic>> fetchAlternatives(String mealRowId,
          {String sort = 'any'}) async =>
      {
        'alternatives': [
          {'code': 'ASC300', 'name': 'Palak paneer', 'kcal': 210, 'protein_g': 11.0},
          {'code': 'ASC301', 'name': 'Chana masala', 'kcal': 230, 'protein_g': 9.0},
        ]
      };

  @override
  Future<Map<String, dynamic>> swapMeal(String mealRowId, String recipeCode,
      {String? fromCode}) async {
    swaps.add('$mealRowId:$fromCode->$recipeCode');
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeAssistant api;
  setUp(() => api = FakeAssistant());

  Future<void> pumpChat(WidgetTester tester,
      {String? initial, VoidCallback? onPlanChanged}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AssistantChat(
              api: api, initialMessage: initial, onPlanChanged: onPlanChanged)),
    ));
    await tester.pumpAndSettle();
  }

  test('stray markdown is stripped from replies', () {
    expect(plainText('**Bold** text\n## Heading\n* item'),
        'Bold text\nHeading\n- item');
  });

  test('day labels', () {
    final now = DateTime(2026, 11, 18, 10);
    expect(dayLabel(DateTime(2026, 11, 18, 8), now), 'Today');
    expect(dayLabel(DateTime(2026, 11, 17, 23), now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 11, 12), now), 'Thu 12 Nov');
  });

  testWidgets('shows saved history with day dividers', (tester) async {
    api.saved = [
      ChatMessage(
          id: '1',
          isUser: true,
          text: 'Old question',
          createdAt: DateTime.now().subtract(const Duration(days: 3))),
      ChatMessage(id: '2', isUser: false, text: 'Old answer'),
    ];
    await pumpChat(tester);
    expect(find.text('Old question'), findsOneWidget);
    expect(find.text('Old answer'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('a proposal is only applied when the user taps Apply',
      (tester) async {
    var changed = 0;
    await pumpChat(tester, onPlanChanged: () => changed++);

    await tester.tap(find.text("Swap tonight's dinner"));
    await tester.pumpAndSettle();
    expect(api.sent, ["Swap tonight's dinner"]);
    expect(find.text('Palak paneer has more protein. Tap Apply to update your plan.'),
        findsOneWidget); // markdown stripped
    expect(find.text('Suggested change'), findsOneWidget);
    expect(find.textContaining('Remembered: Doesn\'t like bhindi'), findsOneWidget);
    expect(api.applied, isEmpty);
    expect(changed, 0);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(api.applied, ['r1']);
    expect(changed, 1);
    expect(find.text('Applied to your plan'), findsOneWidget);
    expect(find.textContaining('Done! Your plan is updated'), findsOneWidget);
  });

  testWidgets('not now dismisses without changing the plan', (tester) async {
    var changed = 0;
    await pumpChat(tester, initial: 'Swap dinner', onPlanChanged: () => changed++);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(api.dismissed, ['r1']);
    expect(changed, 0);
    expect(find.text('Not applied'), findsOneWidget);
  });

  testWidgets('a stale proposal shows as no longer valid', (tester) async {
    api.applyError = const AssistantApiException(
        'Dinner has changed since this was suggested.',
        statusCode: 409);
    await pumpChat(tester, initial: 'Swap dinner');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No longer valid'), findsOneWidget);
  });

  testWidgets('clear chat asks first', (tester) async {
    api.saved = [ChatMessage(id: '1', isUser: true, text: 'hello')];
    await pumpChat(tester);
    await tester.tap(find.byTooltip('Clear chat'));
    await tester.pumpAndSettle();
    expect(api.cleared, isFalse);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Clear chat'));
    await tester.pumpAndSettle();
    expect(api.cleared, isTrue);
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('swap sheet swaps the picked dish with its current code',
      (tester) async {
    final plans = FakeMealPlanApi();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SwapSheet(api: plans, title: 'Swap Thu Dinner', dishes: const [
          Dish(id: 'row-1', code: 'ASC226', name: 'Aloo gobhi'),
          Dish(id: 'row-2', code: 'ASC113', name: 'Chapati'),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Replace Aloo gobhi with:'), findsOneWidget);
    await tester.tap(find.text('Palak paneer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swap to Palak paneer'));
    await tester.pumpAndSettle();
    expect(plans.swaps, ['row-1:ASC226->ASC300']);
  });

  testWidgets('memory card adds and forgets facts', (tester) async {
    api.facts = const [MemoryFact(id: 'm1', fact: "Doesn't like bhindi", kind: 'dislike')];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MemoryCard(api: api)))));
    await tester.pumpAndSettle();
    expect(find.text("Doesn't like bhindi"), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('memory-field')), 'Light dinners on weekdays');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Light dinners on weekdays'), findsOneWidget);

    await tester.tap(find.byTooltip('Forget').first);
    await tester.pumpAndSettle();
    expect(find.text("Doesn't like bhindi"), findsNothing);
    expect(api.facts.map((f) => f.fact), ['Light dinners on weekdays']);
  });
}
