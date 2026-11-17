import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/annora_ui.dart';
import '../../assistant/data/assistant_api.dart';
import '../../assistant/presentation/assistant_chat.dart';
import '../../groceries/presentation/groceries_screen.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/meal_plan_api.dart';
import '../data/plan_models.dart';

const _mealOrder = ['breakfast', 'lunch', 'dinner'];
const _mealColors = {
  'breakfast': Color(0xFF8FC46A),
  'lunch': Color(0xFFF2B544),
  'dinner': Color(0xFFA99BF0),
};
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];

/// The week at a glance: one card per day; the open day shows each meal with
/// portion, nutrition, its ingredients, cooking tips and a swap suggestion.
class MealPlanScreen extends StatefulWidget {
  final MealPlanApi api;
  final AssistantApi? assistantApi;
  final OnboardingRepository? repository;
  final bool isActive;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenProfile;
  final DateTime Function()? clock;

  const MealPlanScreen({
    super.key,
    required this.api,
    this.assistantApi,
    this.repository,
    this.isActive = true,
    this.onOpenHome,
    this.onOpenProfile,
    this.clock,
  });

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late Future<void> _loading = _load();
  ParsedPlan? _plan;
  int? _household;
  DateTime? _openDay;
  bool _confirmRegen = false;
  bool _generating = false;

  // Ingredients by "yyyy-mm-dd|meal_type", loaded on first use.
  Map<String, List<String>>? _ingredients;
  bool _loadingIngredients = false;
  final _shownIngredients = <String>{};

  DateTime get _today => DateUtils.dateOnly((widget.clock ?? DateTime.now)());

  @override
  void didUpdateWidget(covariant MealPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive)
      setState(() {
        _loading = _load();
      });
  }

  Future<void> _load() async {
    try {
      _household =
          (await (widget.repository ?? OnboardingRepository()).fetchProfile())
              ?.familySize;
    } catch (_) {}
    try {
      _plan = parsePlan(await widget.api.fetchMealPlan());
    } on MealPlanApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      _plan = null;
    }
    _ingredients = null;
    _shownIngredients.clear();
    final days = _plan?.days ?? const <DateTime>[];
    if (_openDay == null || !days.contains(_openDay)) {
      _openDay =
          days.contains(_today) ? _today : (days.isEmpty ? null : days.first);
    }
  }

  /// POST /meal-plans/generate {user_id (from session), start_date = today},
  /// then rebuilds the grocery list for the new plan.
  Future<void> _regenerate() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _confirmRegen = false;
    });
    try {
      final result = await widget.api.generateMealPlan(startDate: _today);
      final newPlanId = result['meal_id']?.toString();
      if (newPlanId != null) {
        try {
          await makeGroceryList(widget.api, newPlanId);
        } catch (_) {
          _snack(
              'Your plan is ready. Make the grocery list from the Groceries tab.');
        }
      }
      _openDay = null;
      await _load();
      _snack('Your new plan is ready.');
    } catch (e) {
      _snack("Couldn't make a new plan: $e");
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _toggleIngredients(String key) async {
    if (_shownIngredients.remove(key)) {
      setState(() {});
      return;
    }
    setState(() => _shownIngredients.add(key));
    if (_ingredients != null || _loadingIngredients || _plan?.planId == null)
      return;
    setState(() => _loadingIngredients = true);
    try {
      var data = await widget.api.fetchIngredients(_plan!.planId!);
      if (!_hasIngredients(data)) {
        // Ingredients are saved per plan on first use.
        await widget.api.generateIngredients(_plan!.planId!);
        data = await widget.api.fetchIngredients(_plan!.planId!);
      }
      _ingredients = groupIngredients(data);
    } catch (e) {
      _snack("Couldn't load ingredients: $e");
      _shownIngredients.remove(key);
    } finally {
      if (mounted) setState(() => _loadingIngredients = false);
    }
  }

  static bool _hasIngredients(Map<String, dynamic> data) {
    final meals = data['meals'];
    return meals is List &&
        meals.any((m) =>
            m is Map &&
            m['ingredients'] is List &&
            (m['ingredients'] as List).isNotEmpty);
  }

  void _ask(String question) {
    final api = widget.assistantApi;
    if (api != null) showAssistantSheet(context, api, question);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnnoraPage(
      child: FutureBuilder<void>(
        future: _loading,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.orange));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load your plan",
              body: '${snap.error}',
              action: 'Try again',
              onAction: () => setState(() {
                _loading = _load();
              }),
            );
          }
          final plan = _plan;
          if (plan == null || plan.days.isEmpty) {
            return EmptyState(
              icon: Icons.calendar_month_outlined,
              title: "Let's plan your week",
              body:
                  'Annora builds 7 days of breakfasts, lunches and dinners around your household.',
              action: 'Plan my week',
              busy: _generating,
              onAction: _regenerate,
            );
          }
          return RefreshIndicator(
            color: AppColors.orange,
            onRefresh: () async {
              await _load();
              if (mounted) setState(() {});
            },
            child: _content(plan),
          );
        },
      ),
    );
  }

  Widget _content(ParsedPlan plan) {
    final ended = _today.isAfter(plan.days.last);
    final totals = [for (final d in plan.days) plan.totalsFor(d)];
    final avgKcal =
        totals.fold<double>(0, (a, t) => a + t.kcal) / totals.length;
    final avgProtein =
        totals.fold<double>(0, (a, t) => a + t.protein) / totals.length;
    final unverified = totals.fold<int>(0, (a, t) => a + t.unverified);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        PageTitle(
          title: ended ? 'Your last week' : 'Your week',
          subtitle: [
            _range(plan.days.first, plan.days.last),
            '${plan.days.length} days',
            if (_household != null)
              'for $_household ${_household == 1 ? 'person' : 'people'}',
          ].join(' · '),
        ),
        const SizedBox(height: 16),
        if (ended) ...[
          ConfirmBox(
            message: 'This plan has ended. Plan the week starting today?',
            confirmLabel: 'Plan this week',
            cancelLabel: 'Not now',
            busy: _generating,
            onConfirm: _regenerate,
            onCancel: widget.onOpenHome ?? () {},
          ),
          const SizedBox(height: 16),
        ],
        Row(children: [
          Expanded(
              child: _Stat(
                  label: 'Avg energy',
                  value: fmtInt(avgKcal),
                  unit: 'kcal/day')),
          const SizedBox(width: 8),
          Expanded(
              child: _Stat(
                  label: 'Avg protein',
                  value: avgProtein.round().toString(),
                  unit: 'g/day')),
          const SizedBox(width: 8),
          Expanded(
              child: _Stat(
                  label: 'Dishes',
                  value: '${plan.dishCount}',
                  unit: 'this week')),
        ]),
        const SizedBox(height: 8),
        Text(
          unverified > 0
              ? 'Per person. $unverified ${unverified == 1 ? 'dish has' : 'dishes have'} calorie data that looks wrong and ${unverified == 1 ? 'is' : 'are'} left out of energy.'
              : 'Per person, per day.',
          style: const TextStyle(color: AppColors.textFaint, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        for (final day in plan.days) ...[
          _dayCard(plan, day),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        ACard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Not feeling this week?',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 2),
            const Text(
                'Make a fresh plan from your household settings. Your grocery list is rebuilt too.',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
            const SizedBox(height: 12),
            if (_confirmRegen || _generating)
              ConfirmBox(
                key: const Key('regen-confirm'),
                message: 'This replaces all 7 days of this plan. Continue?',
                confirmLabel: 'Yes, make a new plan',
                cancelLabel: 'Keep this plan',
                busy: _generating,
                onConfirm: _regenerate,
                onCancel: () => setState(() => _confirmRegen = false),
              )
            else
              GhostButton(
                  label: 'Make a new plan',
                  onTap: () => setState(() => _confirmRegen = true)),
          ]),
        ),
      ],
    );
  }

  Widget _dayCard(ParsedPlan plan, DateTime day) {
    final open = day == _openDay;
    final isToday = day == _today;
    final totals = plan.totalsFor(day);
    final meals = plan.menu[day] ?? const <String, List<Dish>>{};

    return Material(
      color: AnnoraUi.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: open ? AnnoraUi.lineStrong : AnnoraUi.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Semantics(
          button: true,
          expanded: open,
          label:
              '${_weekdays[day.weekday - 1]} ${day.day}${isToday ? ', today' : ''}',
          child: InkWell(
            key: Key('plan-day-${_iso(day)}'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _openDay = open ? null : day),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isToday ? AppColors.orange : AnnoraUi.card2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                            _weekdays[day.weekday - 1]
                                .substring(0, 3)
                                .toUpperCase(),
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isToday
                                    ? Colors.white.withValues(alpha: .85)
                                    : AppColors.textFaint)),
                        Text('${day.day}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final type in _mealOrder)
                          if (meals[type]?.isNotEmpty == true)
                            _summaryLine(type, meals[type]!),
                      ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(
                      '${fmtInt(totals.kcal)}${totals.unverified > 0 ? '*' : ''}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5)),
                  const Text('kcal',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  if (isToday)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: AnnoraUi.accentSoft,
                          borderRadius: BorderRadius.circular(999)),
                      child: const Text('TODAY',
                          style: TextStyle(
                              color: AppColors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                ]),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(children: [
              for (final type in _mealOrder)
                if (meals[type]?.isNotEmpty == true)
                  _mealBlock(day, type, meals[type]!),
            ]),
          ),
      ]),
    );
  }

  Widget _summaryLine(String type, List<Dish> dishes) {
    final sides = dishes
        .skip(1)
        .map((d) => d.name.replaceAll(RegExp(r'\s*\(.*\)'), ''))
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: _mealColors[type], shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: dishes.first.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              if (sides.isNotEmpty) TextSpan(text: ' + $sides'),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
          ),
        ),
      ]),
    );
  }

  Widget _mealBlock(DateTime day, String type, List<Dish> dishes) {
    final key = '${_iso(day)}|$type';
    final unverified = dishes.any((d) => d.caloriesUnverified);
    final kcal = dishes
        .where((d) => !d.caloriesUnverified)
        .fold<double>(0, (a, d) => a + d.kcal!);
    final protein = dishes.fold<double>(0, (a, d) => a + (d.protein ?? 0));
    final carbs = dishes.fold<double>(0, (a, d) => a + (d.carbs ?? 0));
    final shown = _shownIngredients.contains(key);
    final ingredients = _ingredients?[key];
    final label = type[0].toUpperCase() + type.substring(1);

    return Container(
      padding: const EdgeInsets.only(top: 12),
      margin: const EdgeInsets.only(top: 2),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AnnoraUi.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: _mealColors[type], shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label.toUpperCase(),
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w600)),
          ),
          Text('${fmtInt(kcal)} kcal${unverified ? '*' : ''}',
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 6),
        Text(dishes.first.name,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.3)),
        if (dishes.length > 1)
          Text('with ${dishes.skip(1).map((d) => d.name).join(', ')}',
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _fact(dishes
              .map((d) =>
                  '1 ${d.unit == null || d.unit!.isEmpty ? 'serving' : d.unit}')
              .join(' + ')),
          _fact('${protein.toStringAsFixed(1)} g protein'),
          _fact('${carbs.round()} g carbs'),
          if (unverified) _fact('Calories unverified', warn: true),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, children: [
          LinkButton(
            label: shown ? 'Hide ingredients' : 'Show ingredients',
            onTap: () => _toggleIngredients(key),
          ),
          if (widget.assistantApi != null) ...[
            LinkButton(
                label: 'Cooking tips',
                onTap: () => _ask('How do I make ${dishes.first.name}?')),
            LinkButton(
              label: 'Swap',
              onTap: () => _ask(
                  'Suggest a swap for ${dishes.first.name}, my $type on ${_weekdays[day.weekday - 1]}, that fits my household\'s diet and goals.'),
            ),
          ],
        ]),
        if (shown)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _loadingIngredients && ingredients == null
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.orange))
                : Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final name in ingredients ?? const <String>[])
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AnnoraUi.lineStrong),
                        ),
                        child: Text(name,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 12.5)),
                      ),
                    if ((ingredients ?? const []).isEmpty)
                      const Text('No ingredient details for this meal.',
                          style: TextStyle(
                              color: AppColors.textFaint, fontSize: 12.5)),
                  ]),
          ),
      ]),
    );
  }

  Widget _fact(String text, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: warn ? const Color(0x1AF2B544) : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                color: warn ? AnnoraUi.warn : AppColors.textMuted,
                fontSize: 12)),
      );

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _range(DateTime a, DateTime b) => a.month == b.month
      ? '${a.day}–${b.day} ${_months[b.month - 1]}'
      : '${a.day} ${_months[a.month - 1].substring(0, 3)} – ${b.day} ${_months[b.month - 1].substring(0, 3)}';
}

/// GET /meal-plans/{id}/ingredients -> {"yyyy-mm-dd|type": [display names]}.
/// The backend returns one entry per planned dish; names are de-duplicated and
/// salt is left out (everyone has it).
Map<String, List<String>> groupIngredients(Map<String, dynamic> response) {
  final grouped = <String, List<String>>{};
  final meals = response['meals'];
  if (meals is! List) return grouped;
  for (final meal in meals.whereType<Map>()) {
    final date = meal['meal_date']?.toString();
    final type = meal['meal_type']?.toString().toLowerCase();
    if (date == null || type == null) continue;
    final list =
        grouped.putIfAbsent('${date.substring(0, 10)}|$type', () => []);
    final items = meal['ingredients'];
    if (items is! List) continue;
    for (final item in items.whereType<Map>()) {
      final name =
          (item['display_name'] ?? item['food_name'] ?? '').toString().trim();
      if (name.isEmpty || name.toLowerCase() == 'salt' || list.contains(name))
        continue;
      list.add(name);
    }
  }
  return grouped;
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _Stat({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AnnoraUi.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AnnoraUi.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: value,
                  style: AppTheme.displayFont
                      .copyWith(fontSize: 21, color: AppColors.textPrimary)),
              TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ])),
          ),
        ]),
      );
}
