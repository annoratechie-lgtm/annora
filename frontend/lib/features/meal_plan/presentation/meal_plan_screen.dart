import 'package:flutter/material.dart';

import '../data/meal_plan_api.dart';

class MealPlanScreen extends StatefulWidget {
  final MealPlanApi api;

  const MealPlanScreen({super.key, required this.api});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  static const _background = Color(0xFFFAF7F1);
  static const _text = Color(0xFF211C18);
  static const _muted = Color(0xFF7B746D);
  static const _orange = Color(0xFFF47A2A);
  static const _green = Color(0xFF4EB68B);
  static const _blue = Color(0xFF5D92D8);
  static const _border = Color(0xFFE8E1D8);

  int _selectedDay = 0;
  int _selectedTab = 0;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchMealPlan();
  }

  void _reload() {
    final future = widget.api.fetchMealPlan();
    setState(() {
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(message: snapshot.error.toString(), onRetry: _reload);
            }
            return _buildContent(snapshot.data ?? const <String, dynamic>{});
          },
        ),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final plan = Map<String, dynamic>.from(data['meal_plan'] ?? {});
    final rawMeals = (data['meals'] as List? ?? const []);
    final meals = rawMeals.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final dates = meals
        .map((e) => e['meal_date']?.toString())
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    if (dates.isEmpty) {
      return _ErrorState(message: 'No meals are available for this plan yet.', onRetry: _reload);
    }

    final safeDay = _selectedDay.clamp(0, dates.length - 1).toInt();
    if (safeDay != _selectedDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedDay = safeDay);
      });
    }

    final selectedDate = dates[safeDay];
    final dayMeals = meals.where((e) => e['meal_date']?.toString() == selectedDate).toList();

    return Column(
      children: [
        _buildDayStrip(dates),
        _buildTabs(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 22),
              children: [
                _buildDayTitle(selectedDate, plan),
                const SizedBox(height: 10),
                if (_selectedTab == 0) ...[
                  for (final meal in dayMeals) _buildMealCard(meal),
                  const SizedBox(height: 12),
                  _buildNutritionSummary(),
                ] else if (_selectedTab == 1)
                  _buildNutritionTab()
                else if (_selectedTab == 2)
                  _buildPantryTab()
                else
                  _buildAssistTab(),
              ],
            ),
          ),
        ),
        _buildBottomNav(),
      ],
    );
  }

  Widget _buildDayStrip(List<String> dates) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 9),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < dates.length && i < 7; i++)
            Expanded(child: _dayChip(i, dates[i])),
        ],
      ),
    );
  }

  Widget _dayChip(int index, String iso) {
    final date = DateTime.tryParse(iso) ?? DateTime.now();
    final selected = index == _selectedDay;
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final dayLabel = weekdays[date.weekday - 1];
    return GestureDetector(
      onTap: () => setState(() => _selectedDay = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7F5EC) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(dayLabel, style: TextStyle(fontSize: 10, color: selected ? _green : _muted)),
            const SizedBox(height: 2),
            Text('${date.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: selected ? _green : _text)),
            const SizedBox(height: 2),
            Container(width: 5, height: 5, decoration: BoxDecoration(color: selected ? _green : _muted, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    const tabs = [('🍴', 'Meals'), ('📊', 'Nutrition'), ('🌿', 'From Pantry'), ('⚡', 'Assist')];
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _border))),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == _selectedTab ? _orange : Colors.transparent, width: 2))),
                  child: Text('${tabs[i].$1} ${tabs[i].$2}', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: i == _selectedTab ? _orange : _muted)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayTitle(String iso, Map<String, dynamic> plan) {
    final date = DateTime.tryParse(iso) ?? DateTime.now();
    final start = DateTime.tryParse(plan['start_date']?.toString() ?? '');
    final label = start != null && DateUtils.isSameDay(start, date) ? 'Today' : _formatDate(date);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text)),
        Text(_formatDate(date), style: const TextStyle(fontSize: 10.5, color: _muted)),
      ],
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal) {
    final type = meal['meal_type']?.toString() ?? 'meal';
    final name = meal['name']?.toString() ?? 'Meal';
    final icon = type == 'breakfast' ? '🌞' : type == 'lunch' ? '🍲' : '🌙';
    final color = type == 'breakfast' ? _orange : type == 'lunch' ? _green : _blue;
    final cooked = meal['status']?.toString() == 'cooked';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4))]),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('$icon ${type.toUpperCase()}', style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: color, fontWeight: FontWeight.w600)),
            const Spacer(),
            _pill(cooked ? '✓ Done' : '⏰ Upcoming', cooked ? const Color(0xFFE5F4ED) : const Color(0xFFFFF1D9), cooked ? const Color(0xFF2D9070) : const Color(0xFFB96A14)),
          ]),
          const Divider(height: 18, color: _border),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withOpacity(.18), borderRadius: BorderRadius.circular(14)), child: Center(child: Text(type == 'breakfast' ? '🥣' : type == 'lunch' ? '🍛' : '🍽️', style: const TextStyle(fontSize: 24)))),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _text)),
              const SizedBox(height: 4),
              const Text('Planned for your household', style: TextStyle(fontSize: 10.5, color: _muted)),
              const SizedBox(height: 7),
              Wrap(spacing: 6, children: [
                _pill('🌿 Veg', const Color(0xFFE5F4ED), const Color(0xFF2D9070)),
                _pill('✦ AI suggested', const Color(0xFFF0E9FF), const Color(0xFF8057D8)),
              ]),
            ])),
          ]),
        ]),
      ),
    );
  }

  Widget _buildNutritionSummary() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("📊 Today's nutrition summary", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _text)),
        const SizedBox(height: 11),
        _progressRow('Calories', 0.84, '1,680/2,000', _orange),
        _progressRow('Protein', 0.55, '44/80g', _blue),
        _progressRow('Carbs', 0.80, '200/250g', const Color(0xFFF3B72D)),
        _progressRow('Fat', 0.52, '32/70g', const Color(0xFFF1A05B)),
      ]),
    );
  }

  Widget _progressRow(String label, double value, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 55, child: Text(label, style: const TextStyle(fontSize: 10.5, color: _text))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: value, minHeight: 7, backgroundColor: const Color(0xFFEDE8DF), valueColor: AlwaysStoppedAnimation(color)))),
        const SizedBox(width: 9),
        SizedBox(width: 66, child: Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 9.5, color: _muted))),
      ]),
    );
  }

  Widget _buildNutritionTab() => _simpleCard('📊 Nutrition', 'Nutrition values will appear here once the meal nutrition data is populated.');
  Widget _buildPantryTab() => _simpleCard('🌿 From Pantry', 'Pantry matching will appear here when pantry inventory is connected.');
  Widget _buildAssistTab() => _simpleCard('⚡ Annora Assist', 'Ask Annora for swaps and meal suggestions in a future iteration.');

  Widget _simpleCard(String title, String body) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _text)), const SizedBox(height: 8), Text(body, style: const TextStyle(fontSize: 11, color: _muted, height: 1.4))]));
  }

  Widget _buildBottomNav() {
    const items = [('⌂', 'Home'), ('▦', 'Plan'), ('🛒', 'Shop'), ('📦', 'Pantry'), ('♟', 'Profile')];
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _border))),
      padding: const EdgeInsets.only(top: 7, bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (var i = 0; i < items.length; i++) _NavItem(icon: items[i].$1, label: items[i].$2, selected: i == 1),
      ]),
    );
  }

  Widget _pill(String text, Color background, Color foreground) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)), child: Text(text, style: TextStyle(fontSize: 8.5, color: foreground)));

  String _formatDate(DateTime date) => '${date.day}/${date.month}';
}

class _NavItem extends StatelessWidget {
  final String icon;
  final String label;
  final bool selected;
  const _NavItem({required this.icon, required this.label, required this.selected});
  @override
  Widget build(BuildContext context) => SizedBox(width: 52, child: Column(mainAxisSize: MainAxisSize.min, children: [Text(icon, style: TextStyle(fontSize: 18, color: selected ? const Color(0xFFF47A2A) : const Color(0xFF6E6259))), const SizedBox(height: 2), Text(label, style: TextStyle(fontSize: 8.5, color: selected ? const Color(0xFFF47A2A) : const Color(0xFF8A8179)))]));
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('🍽️', style: TextStyle(fontSize: 38)), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6E6259))), const SizedBox(height: 12), FilledButton(onPressed: onRetry, child: const Text('Retry'))])));
}
