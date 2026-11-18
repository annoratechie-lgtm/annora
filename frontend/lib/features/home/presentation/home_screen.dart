import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../assistant/data/assistant_api.dart';
import '../../assistant/presentation/assistant_chat.dart';
import '../../groceries/presentation/groceries_screen.dart';
import '../../meal_plan/data/meal_plan_api.dart';
import '../../meal_plan/data/plan_models.dart';
import '../../onboarding/data/onboarding_repository.dart';

// Palette (dark, matches login + onboarding)
const _bg = AppColors.background;
const _card = Color(0xFF1E1815);
const _card2 = Color(0xFF261F1A);
const _field = Color(0xFF1A1411);
const _line = Color(0x14FFFFFF);
const _lineStrong = Color(0x26FFFFFF);
const _accentSoft = Color(0x24FF7A3D);
const _warn = Color(0xFFF2B544);
const _mealColors = {
  'breakfast': Color(0xFF8FC46A),
  'lunch': Color(0xFFF2B544),
  'dinner': Color(0xFFA99BF0),
};
const _mealIcons = {
  'breakfast': Icons.wb_twilight_rounded,
  'lunch': Icons.wb_sunny_outlined,
  'dinner': Icons.nightlight_round,
};
const _mealOrder = ['breakfast', 'lunch', 'dinner'];

/// Post-onboarding home: this week's plan (day strip), the selected day's
/// meals, day totals with a weekly calorie chart, groceries, Ask Annora and
/// a one-line household summary.
class HomeScreen extends StatefulWidget {
  final MealPlanApi? mealPlanApi;
  final AssistantApi? assistantApi;
  final OnboardingRepository? repository;
  final VoidCallback? onOpenMealPlan;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenGroceries;
  final bool isActive;

  /// Overridable for tests.
  final DateTime Function()? clock;
  final String? displayName;

  const HomeScreen({
    super.key,
    this.mealPlanApi,
    this.assistantApi,
    this.repository,
    this.onOpenMealPlan,
    this.onOpenProfile,
    this.onOpenGroceries,
    this.isActive = true,
    this.clock,
    this.displayName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<HomeData> _data = _load();
  DateTime? _selected;
  bool _generating = false;
  bool _buildingGroceries = false;
  final _askController = TextEditingController();

  DateTime get _today => DateUtils.dateOnly((widget.clock ?? DateTime.now)());

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Coming back to Home (e.g. after generating a plan on the Plan tab): refresh.
    if (!oldWidget.isActive && widget.isActive) _reload();
  }

  @override
  void dispose() {
    _askController.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _data = _load();
      });

  Future<HomeData> _load() async {
    final repo = widget.repository ?? OnboardingRepository();
    final profile = await repo.fetchProfile();
    final exclusions = await repo.fetchDietaryExclusions();
    final api = widget.mealPlanApi;
    if (api == null) return HomeData(profile: profile, exclusions: exclusions);

    Map<String, dynamic> plan;
    try {
      plan = await api.fetchMealPlan();
    } on MealPlanApiException catch (e) {
      if (e.statusCode == 404)
        return HomeData(profile: profile, exclusions: exclusions);
      return HomeData(
          profile: profile, exclusions: exclusions, error: e.message);
    } catch (e) {
      return HomeData(profile: profile, exclusions: exclusions, error: '$e');
    }

    final parsed = parsePlan(plan);
    GrocerySummary? grocery;
    if (parsed.planId != null) {
      try {
        final items =
            parseGroceryItems(await api.fetchGroceryList(parsed.planId!));
        grocery = GrocerySummary(
          items: items.length,
          bought: items.where((i) => i.purchased).length,
          urgent: items.where((i) => i.urgent).length,
        );
      } on MealPlanApiException catch (e) {
        if (e.statusCode != 404)
          grocery = null; // treat other errors as "no list" on Home
      } catch (_) {}
    }
    return HomeData(
        profile: profile,
        exclusions: exclusions,
        plan: parsed,
        grocery: grocery);
  }

  // ---------- actions (each sends exactly what the backend expects) ----------

  /// POST /meal-plans/generate {user_id, start_date}. user_id comes from the
  /// signed-in session inside MealPlanApi; start_date is today, or the day
  /// after the current plan ends when planning next week.
  Future<void> _generate({DateTime? startDate}) async {
    final api = widget.mealPlanApi;
    if (api == null || _generating) return;
    setState(() => _generating = true);
    try {
      await api.generateMealPlan(startDate: startDate ?? _today);
      if (!mounted) return;
      _selected = null;
      _reload();
      _snack('Your meal plan is ready.');
    } catch (e) {
      _snack("Couldn't plan your week: $e");
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _makeGroceries(String planId) async {
    final api = widget.mealPlanApi;
    if (api == null || _buildingGroceries) return;
    setState(() => _buildingGroceries = true);
    try {
      await makeGroceryList(api, planId);
      if (!mounted) return;
      _reload();
      _snack('Your grocery list is ready.');
    } catch (e) {
      _snack("Couldn't make the grocery list: $e");
    } finally {
      if (mounted) setState(() => _buildingGroceries = false);
    }
  }

  Future<void> _openAssistant([String? question]) async {
    final api = widget.assistantApi;
    if (api == null) return;
    // Home stays the active tab while the sheet is open, so reload here.
    if (await showAssistantSheet(context, api, question) && mounted) _reload();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: widget.assistantApi == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'ask-annora',
              onPressed: _openAssistant,
              backgroundColor: AppColors.textPrimary,
              foregroundColor: _bg,
              icon: const Icon(Icons.auto_awesome,
                  color: AppColors.orange, size: 18),
              label: const Text('Ask',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
      body: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -1.25),
                radius: 0.9,
                colors: [Color(0x598A4A24), Color(0x008A4A24)],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: FutureBuilder<HomeData>(
                future: _data,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.orange));
                  }
                  if (snap.hasError) {
                    return _ErrorView(
                        message: '${snap.error}', onRetry: _reload);
                  }
                  return RefreshIndicator(
                    color: AppColors.orange,
                    onRefresh: () async => _reload(),
                    child: _buildContent(snap.data!),
                  );
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildContent(HomeData data) {
    final plan = data.plan;
    final today = _today;
    final activePlan =
        plan != null && plan.days.isNotEmpty && !today.isAfter(plan.days.last);
    if (activePlan) {
      final days = plan.days;
      if (_selected == null || !days.contains(_selected)) {
        _selected = days.contains(today) ? today : days.first;
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _header(),
        const SizedBox(height: 18),
        if (data.error != null) ...[
          _ErrorView(message: data.error!, onRetry: _reload, compact: true),
          const SizedBox(height: 18),
        ] else if (activePlan) ...[
          _weekStrip(plan),
          if (plan.days.last.difference(today).inDays <= 1) ...[
            const SizedBox(height: 16),
            _endingBanner(plan),
          ],
          const SizedBox(height: 20),
          _sectionLabel(
              _isToday(_selected!)
                  ? "Today's menu"
                  : "${_weekday(_selected!)}'s menu",
              'per person'),
          const SizedBox(height: 10),
          ..._mealCards(plan.menu[_selected] ?? const {}),
          const SizedBox(height: 18),
          _sectionLabel(
              _isToday(_selected!)
                  ? "Today's total"
                  : "${_weekday(_selected!)}'s total",
              'per person'),
          const SizedBox(height: 10),
          _totalsCard(plan),
          const SizedBox(height: 18),
        ] else ...[
          _planHero(data),
          const SizedBox(height: 18),
        ],
        _groceryCard(data, activePlan),
        const SizedBox(height: 14),
        if (widget.assistantApi != null) ...[
          _askCard(),
          const SizedBox(height: 14),
        ],
        if (data.profile != null) _householdLine(data),
      ],
    );
  }

  Widget _header() {
    final now = (widget.clock ?? DateTime.now)();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final name = widget.displayName ?? _firstName();
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_weekday(now)}, ${now.day} ${_month(now)}',
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(name == null ? greeting : '$greeting, $name',
              style: AppTheme.displayFont.copyWith(
                  fontSize: 27, height: 1.1, color: AppColors.textPrimary)),
        ]),
      ),
      Semantics(
        button: true,
        label: 'Open profile',
        child: InkWell(
          onTap: widget.onOpenProfile,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.avatarGold,
            child: Text((name ?? 'A').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: _bg, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ),
    ]);
  }

  String? _firstName() {
    try {
      final meta =
          Supabase.instance.client.auth.currentUser?.userMetadata ?? const {};
      final full = (meta['full_name'] ?? meta['name'] ?? meta['display_name'])
          ?.toString()
          .trim();
      if (full == null || full.isEmpty) return null;
      return full.split(RegExp(r'\s+')).first;
    } catch (_) {
      return null;
    }
  }

  Widget _weekStrip(ParsedPlan plan) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text.rich(TextSpan(
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            children: [
              const TextSpan(text: "This week's plan · "),
              TextSpan(
                  text: _range(plan.days.first, plan.days.last),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          )),
        ),
        _LinkButton(label: 'Full plan', onTap: widget.onOpenMealPlan),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < plan.days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _dayChip(plan.days[i])),
        ],
      ]),
    ]);
  }

  Widget _dayChip(DateTime day) {
    final selected = day == _selected;
    final isToday = _isToday(day);
    return Semantics(
      button: true,
      selected: selected,
      label: '${_weekday(day)} ${day.day}${isToday ? ', today' : ''}',
      child: Material(
        color: selected ? AppColors.orange : _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.orange : _line),
        ),
        child: InkWell(
          key: Key('day-${_iso(day)}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = day),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ExcludeSemantics(
              child: Column(children: [
                Text(_weekday(day).substring(0, 3).toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .4,
                        color: selected
                            ? Colors.white.withValues(alpha: .85)
                            : AppColors.textFaint)),
                Text('${day.day}',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color:
                            selected ? Colors.white : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday
                        ? (selected ? Colors.white : AppColors.orange)
                        : Colors.transparent,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _endingBanner(ParsedPlan plan) {
    final last = plan.days.last;
    final endsToday = _isToday(last);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x59FF7A3D)),
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(endsToday ? 'Your plan ends today' : 'Your plan ends tomorrow',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            const SizedBox(height: 2),
            const Text('Plan next week so meals and groceries keep coming.',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 10),
        _PrimaryButton(
          key: const Key('plan-next-week'),
          label: 'Plan next week',
          busy: _generating,
          // Next plan starts the day after this one ends.
          onTap: () => _generate(startDate: last.add(const Duration(days: 1))),
        ),
      ]),
    );
  }

  List<Widget> _mealCards(Map<String, List<Dish>> meals) {
    final cards = <Widget>[];
    for (final type in _mealOrder) {
      final dishes = meals[type];
      if (dishes == null || dishes.isEmpty) continue;
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 10));
      cards.add(_MealCard(
          type: type,
          dishes: dishes,
          onAsk: widget.assistantApi == null ? null : _openAssistant));
    }
    if (cards.isEmpty) {
      cards.add(const _Note('No meals planned for this day.'));
    }
    return cards;
  }

  Widget _totalsCard(ParsedPlan plan) {
    final totals = plan.totalsFor(_selected!);
    final weekly = [for (final d in plan.days) plan.totalsFor(d).kcal];
    final avg =
        weekly.isEmpty ? 0.0 : weekly.reduce((a, b) => a + b) / weekly.length;
    final maxKcal = weekly.fold<double>(1, (m, v) => v > m ? v : m);
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: _Stat(
                  label: 'Energy', value: fmtInt(totals.kcal), unit: 'kcal')),
          const SizedBox(width: 8),
          Expanded(
              child: _Stat(
                  label: 'Protein',
                  value: totals.protein.toStringAsFixed(1),
                  unit: 'g')),
          const SizedBox(width: 8),
          Expanded(
              child: _Stat(
                  label: 'Carbs',
                  value: totals.carbs.round().toString(),
                  unit: 'g')),
        ]),
        const SizedBox(height: 10),
        Text(
          totals.unverified > 0
              ? '* ${totals.unverified} ${totals.unverified == 1 ? 'dish' : 'dishes'} left out of calories: the recipe data looks wrong.'
              : 'Breakfast, lunch and dinner for one person.',
          style: TextStyle(
              color: totals.unverified > 0 ? _warn : AppColors.textFaint,
              fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(
              child: Text('Calories this week',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
          Text('avg ${fmtInt(avg)} kcal/day',
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < plan.days.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: plan.days[i] == _selected,
                  label: '${_weekday(plan.days[i])}: ${fmtInt(weekly[i])} kcal',
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = plan.days[i]),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (plan.days[i] == _selected)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: FittedBox(
                                child: Text(fmtInt(weekly[i]),
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: (weekly[i] / maxKcal * 72)
                                .clamp(4, 72)
                                .toDouble(),
                            decoration: BoxDecoration(
                              color: plan.days[i] == _selected
                                  ? AppColors.orange
                                  : const Color(0x24FFFFFF),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                  bottom: Radius.circular(2)),
                            ),
                          ),
                        ]),
                  ),
                ),
              ),
            ],
          ]),
        ),
        const Divider(height: 1, color: _line),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < plan.days.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Text(_weekday(plan.days[i]).substring(0, 1),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 11)),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _planHero(HomeData data) {
    final p = data.profile;
    final ended = data.plan != null && data.plan!.days.isNotEmpty;
    final bullets = <String>[
      if (p != null) _dietSentence(p),
      if (p != null)
        'Portions for ${p.familySize} ${p.familySize == 1 ? 'person' : 'people'}',
      if (data.exclusions.isNotEmpty)
        'Nothing with ${data.exclusions.take(3).join(', ')}${data.exclusions.length > 3 ? '…' : ''}',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C1F17), _card],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ended ? 'Plan your next week' : "Let's plan your week",
            style: AppTheme.displayFont.copyWith(
                fontSize: 26, height: 1.1, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          ended
              ? 'Your last plan ended on ${data.plan!.days.last.day} ${_month(data.plan!.days.last)}.'
              : 'Annora builds 7 days of breakfasts, lunches and dinners around your household.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 14),
        for (final b in bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_rounded,
                  color: AppColors.orange, size: 18),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(b,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14))),
            ]),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: _PrimaryButton(
            key: const Key('plan-my-week'),
            label: 'Plan my week',
            icon: Icons.auto_awesome,
            big: true,
            busy: _generating,
            onTap: widget.mealPlanApi == null ? null : () => _generate(),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text('Takes about 20 seconds · You can swap any meal later',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _groceryCard(HomeData data, bool activePlan) {
    final planId = data.plan?.planId;
    final g = data.grocery;
    if (!activePlan || planId == null) {
      return const _Card(
        child: _IconRow(
          icon: Icons.shopping_bag_outlined,
          title: 'Groceries',
          body: 'Your grocery list appears here once your week is planned.',
        ),
      );
    }
    if (g == null) {
      final dishCount = data.plan!.dishCount;
      return _Card(
        child: Column(children: [
          _IconRow(
            icon: Icons.shopping_bag_outlined,
            title: 'No grocery list yet',
            body: "Turn this week's $dishCount dishes into one shopping list.",
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              key: const Key('make-grocery-list'),
              label: 'Make grocery list',
              big: true,
              busy: _buildingGroceries,
              onTap: () => _makeGroceries(planId),
            ),
          ),
        ]),
      );
    }
    return _Card(
      child: Column(children: [
        Row(children: [
          Expanded(
            child: _IconRow(
              icon: Icons.shopping_bag_outlined,
              title: "This week's groceries",
              body: g.bought > 0
                  ? '${g.bought} of ${g.items} items bought${g.urgent > 0 ? ' · ${g.urgent} urgent' : ''}'
                  : '${g.items} items${g.urgent > 0 ? ' · ${g.urgent} urgent' : ''}',
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: widget.onOpenGroceries,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: _lineStrong),
              shape: const StadiumBorder(),
            ),
            child: const Text('Open'),
          ),
        ]),
        if (g.items > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: g.bought / g.items,
              minHeight: 6,
              backgroundColor: const Color(0x14FFFFFF),
              color: AppColors.orange,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _askCard() {
    const suggestions = [
      "Swap tonight's dinner",
      'Make tomorrow lighter',
      'What can I make with leftover rice?'
    ];
    void submit() {
      final q = _askController.text.trim();
      _askController.clear();
      _openAssistant(q.isEmpty ? null : q);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1F18), _card],
          stops: [0, .6],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _IconRow(
          icon: Icons.auto_awesome,
          title: 'Ask Annora',
          body: 'Swap meals, plan a fresh week or ask how to cook anything. Annora asks before changing your plan.',
        ),
        const SizedBox(height: 12),
        Container(
          height: 50,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: _field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: const Key('ask-field'),
                controller: _askController,
                onSubmitted: (_) => submit(),
                textInputAction: TextInputAction.send,
                cursorColor: AppColors.orange,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: 'Ask anything about food or your plan',
                  hintStyle: TextStyle(
                      color: AppColors.textFaint, fontWeight: FontWeight.w400),
                ),
              ),
            ),
            Material(
              color: AppColors.orange,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: submit,
                child: const SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 18, semanticLabel: 'Ask'),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in suggestions)
            ActionChip(
              label: Text(s),
              onPressed: () => _openAssistant(s),
              backgroundColor: const Color(0x08FFFFFF),
              side: const BorderSide(color: _lineStrong),
              shape: const StadiumBorder(),
              labelStyle:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
        ]),
      ]),
    );
  }

  Widget _householdLine(HomeData data) {
    final p = data.profile!;
    final goals =
        p.dietaryGoals.where((g) => g != 'no_preference').map(_pretty).toList();
    final parts = <InlineSpan>[
      const TextSpan(text: 'Planning for '),
      _b('${p.familySize} ${p.familySize == 1 ? 'person' : 'people'}'),
      const TextSpan(text: ' · '),
      _b(_pretty(p.dietaryPreference)),
      const TextSpan(text: ' · '),
      _b('₹${fmtInt(p.monthlyBudget)}'),
      const TextSpan(text: '/mo'),
      if (goals.isNotEmpty) ...[
        const TextSpan(text: ' · '),
        _b(goals.join(', '))
      ],
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line)),
      child: Row(children: [
        Expanded(
          child: Text.rich(TextSpan(
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              children: parts)),
        ),
        _LinkButton(label: 'Edit', onTap: widget.onOpenProfile),
      ]),
    );
  }

  // ---------- helpers ----------
  TextSpan _b(String s) => TextSpan(
      text: s,
      style: const TextStyle(
          color: AppColors.textPrimary, fontWeight: FontWeight.w600));

  Widget _sectionLabel(String title, String hint) => Row(children: [
        Expanded(
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600)),
        ),
        Text(hint,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
      ]);

  bool _isToday(DateTime d) => d == _today;
  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _weekday(DateTime d) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ][d.weekday - 1];
  static String _month(DateTime d) => const [
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
      ][d.month - 1];
  static String _range(DateTime a, DateTime b) {
    final mon = _month(b).substring(0, 3);
    return a.month == b.month
        ? '${a.day}–${b.day} $mon'
        : '${a.day} ${_month(a).substring(0, 3)} – ${b.day} $mon';
  }

  static String _pretty(String v) => v
      .split('_')
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ')
      .replaceFirst('Non Vegetarian', 'Non-vegetarian');

  static String _dietSentence(OnboardingProfile p) {
    final diet = switch (p.dietaryPreference) {
      'vegetarian' => 'Only vegetarian recipes',
      'eggetarian' => 'Vegetarian recipes plus eggs',
      'vegan' => 'Only vegan recipes',
      'non_vegetarian' => 'Vegetarian and non-vegetarian recipes',
      _ => 'Recipes from every diet',
    };
    final goals = p.dietaryGoals
        .where((g) => g != 'no_preference')
        .map((g) => _pretty(g).toLowerCase())
        .toList();
    return goals.isEmpty ? diet : '$diet, ${goals.join(' and ')}';
  }
}

class GrocerySummary {
  final int items;
  final int bought;
  final int urgent;
  const GrocerySummary(
      {required this.items, required this.bought, required this.urgent});
}

class HomeData {
  final OnboardingProfile? profile;
  final List<String> exclusions;
  final ParsedPlan? plan;
  final GrocerySummary? grocery;
  final String? error;

  const HomeData(
      {this.profile,
      this.exclusions = const [],
      this.plan,
      this.grocery,
      this.error});
}

// ---------- widgets ----------

class _MealCard extends StatelessWidget {
  final String type;
  final List<Dish> dishes;
  final void Function([String?])? onAsk;

  const _MealCard({required this.type, required this.dishes, this.onAsk});

  @override
  Widget build(BuildContext context) {
    final color = _mealColors[type]!;
    final main = dishes.first;
    final sides = dishes.skip(1).toList();
    final unverified = dishes.any((d) => d.caloriesUnverified);
    final kcal = dishes
        .where((d) => !d.caloriesUnverified)
        .fold<double>(0, (a, d) => a + d.kcal!);
    final protein = dishes.fold<double>(0, (a, d) => a + (d.protein ?? 0));
    final carbs = dishes.fold<double>(0, (a, d) => a + (d.carbs ?? 0));
    final servings = dishes
        .map((d) =>
            '1 ${d.unit == null || d.unit!.isEmpty ? 'serving' : d.unit}')
        .join(' + ');
    final label = type[0].toUpperCase() + type.substring(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(_mealIcons[type], color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(label.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w600)),
              ),
              Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: fmtInt(kcal),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    TextSpan(text: ' kcal${unverified ? '*' : ''}'),
                  ]),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13)),
            ]),
            const SizedBox(height: 4),
            Text(main.name,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3)),
            if (sides.isNotEmpty)
              Text('with ${sides.map((s) => s.name).join(', ')}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _Fact(servings),
              _Fact('${protein.toStringAsFixed(1)} g protein'),
              _Fact('${carbs.round()} g carbs'),
              if (unverified) const _Fact('Calories unverified', warn: true),
            ]),
            if (onAsk != null)
              TextButton.icon(
                onPressed: () => onAsk!('How do I make ${main.name}?'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  padding: const EdgeInsets.only(top: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('Cooking tips',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  final String text;
  final bool warn;
  const _Fact(this.text, {this.warn = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: warn ? const Color(0x1AF2B544) : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                color: warn ? _warn : AppColors.textMuted, fontSize: 12)),
      );
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
            color: _card2, borderRadius: BorderRadius.circular(12)),
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
                      .copyWith(fontSize: 22, color: AppColors.textPrimary)),
              TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ])),
          ),
        ]),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line)),
        child: child,
      );
}

class _IconRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _IconRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: _accentSoft, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: AppColors.orange, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(body,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
        ),
      ]);
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool big;
  final IconData? icon;

  const _PrimaryButton(
      {super.key,
      required this.label,
      required this.onTap,
      this.busy = false,
      this.big = false,
      this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: big ? 54 : 40,
        child: ElevatedButton(
          onPressed: busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0x99FF7A3D),
            disabledForegroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: big ? 20 : 14),
            shape: const StadiumBorder(),
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8)
                  ],
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: big ? 16 : 14)),
                  ),
                ]),
        ),
      );
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _LinkButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => _Card(
      child: Text(text, style: const TextStyle(color: AppColors.textMuted)));
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool compact;
  const _ErrorView(
      {required this.message, required this.onRetry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final body = _Card(
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Text("Couldn't load your plan. $message",
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        TextButton(
            onPressed: onRetry,
            child:
                const Text('Retry', style: TextStyle(color: AppColors.orange))),
      ]),
    );
    return compact
        ? body
        : Padding(
            padding: const EdgeInsets.all(16), child: Center(child: body));
  }
}
