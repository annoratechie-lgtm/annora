import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../meal_plan/data/meal_plan_api.dart';
import '../../onboarding/data/onboarding_repository.dart';

/// Post-onboarding home screen.
///
/// Home summary backed by the signed-in user profile and active meal plan.
class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenMealPlan;
  final MealPlanApi? mealPlanApi;

  const HomeScreen({super.key, this.onOpenMealPlan, this.mealPlanApi});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedNav = 0;
  late Future<_HomeData> _homeData;

  static const _background = Color(0xFFFAF7F1);
  static const _text = Color(0xFF171411);
  static const _muted = Color(0xFF7B746D);
  static const _orange = Color(0xFFF47A2A);
  static const _green = Color(0xFF4EB68B);
  static const _blue = Color(0xFF5D92D8);
  static const _purple = Color(0xFF8B5BEA);
  static const _border = Color(0xFFE8E1D8);

  @override
  void initState() {
    super.initState();
    _homeData = _loadHomeData();
  }

  Future<_HomeData> _loadHomeData() async {
    final repository = OnboardingRepository();
    final profile = await repository.fetchProfile();
    final exclusions = await repository.fetchDietaryExclusions();
    final today = DateTime.now();
    final dateKey = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    var meals = <Map<String, dynamic>>[];
    if (widget.mealPlanApi != null) {
      try {
        final plan = await widget.mealPlanApi!.fetchMealPlan();
        final rows = plan['meals'];
        if (rows is List) {
          meals = rows.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .where((row) => row['meal_date']?.toString() == dateKey)
              .toList();
        }
      } catch (_) {
        // A profile without an active meal plan still has a useful home screen.
      }
    }
    return _HomeData(profile, exclusions, meals);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<_HomeData>(
                      future: _homeData,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 100),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final data = snapshot.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 16),
                            _buildProfileCard(data),
                            const SizedBox(height: 24),
                            _sectionLabel("TODAY'S MEALS"),
                            const SizedBox(height: 8),
                            _buildMealsCard(data?.meals ?? const []),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final fullName = (metadata['full_name'] ?? metadata['name'] ?? metadata['display_name'])?.toString().trim();
    final name = fullName?.isNotEmpty == true ? fullName!.split(RegExp(r'\s+')).first : (user?.email?.split('@').first ?? 'there');
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$greeting · ${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}', style: const TextStyle(fontSize: 12, color: _muted)),
      const SizedBox(height: 3),
      RichText(text: TextSpan(style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _text), children: [
        TextSpan(text: "$name's "),
        const TextSpan(text: 'Kitchen', style: TextStyle(color: _orange)),
      ])),
    ]);
  }

  String _weekday(int day) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1];
  String _month(int month) => const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][month - 1];

  Widget _buildProfileCard(_HomeData? data) {
    final profile = data?.profile;
    if (profile == null) return const SizedBox.shrink();
    final goals = profile.dietaryGoals.where((goal) => goal != 'no_preference');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF2E5), Color(0xFFF9F3EA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0DFCC)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.tune_rounded, color: _orange, size: 18),
          SizedBox(width: 7),
          Text('YOUR KITCHEN', style: TextStyle(fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: _muted)),
        ]),
        const SizedBox(height: 13),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _ProfileChip(icon: Icons.people_outline, label: '${profile.familySize} ${profile.familySize == 1 ? 'person' : 'people'}'),
          _ProfileChip(icon: Icons.account_balance_wallet_outlined, label: '₹${_formatBudget(profile.monthlyBudget)} / month'),
          _ProfileChip(icon: Icons.restaurant_outlined, label: _prettyLabel(profile.dietaryPreference)),
          for (final goal in goals) _ProfileChip(icon: Icons.flag_outlined, label: _prettyLabel(goal)),
          for (final item in data?.exclusions ?? const <String>[]) _ProfileChip(icon: Icons.remove_circle_outline, label: 'Avoid $item'),
        ]),
      ]),
    );
  }

  String _prettyLabel(String value) => value.split('_').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');
  String _formatBudget(double amount) => amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);

  Widget _buildMealsCard(List<Map<String, dynamic>> meals) {
    final grouped = <String, List<String>>{};
    for (final meal in meals) {
      final type = meal['meal_type']?.toString().toLowerCase() ?? 'meal';
      final name = meal['name']?.toString().trim();
      final code = meal['source_recipe_code']?.toString().trim();
      final title = name == null || name.isEmpty || name == 'NA' ? (code ?? 'Meal') : name;
      grouped.putIfAbsent(type, () => []).add(title);
    }
    const types = ['breakfast', 'lunch', 'dinner'];
    final visibleTypes = types.where(grouped.containsKey).toList();
    if (visibleTypes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: Row(children: [
          const Icon(Icons.event_note_outlined, color: _muted),
          const SizedBox(width: 10),
          const Expanded(child: Text('No meals planned for today yet.', style: TextStyle(fontSize: 13, color: _muted))),
          TextButton(onPressed: widget.onOpenMealPlan, child: const Text('View plan')),
        ]),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [
        BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, 4)),
      ]),
      child: Column(children: [
        for (var i = 0; i < visibleTypes.length; i++) ...[
          _MealRow(meal: _Meal(grouped[visibleTypes[i]]!.join(', '), _prettyLabel(visibleTypes[i]), '', _orange)),
          if (i != visibleTypes.length - 1) const Divider(height: 1, indent: 14, endIndent: 14, color: _border),
        ],
      ]),
    );
  }

  Widget _buildBottomNav() {
    const items = [
      ('⌂', 'Home'),
      ('▦', 'Plan'),
      ('🛒', 'Shop'),
      ('📦', 'Pantry'),
      ('♙', 'Profile'),
    ];
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _border))),
      padding: const EdgeInsets.only(top: 7, bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (var i = 0; i < items.length; i++)
          GestureDetector(
            onTap: () {
              if (i == 1 && widget.onOpenMealPlan != null) {
                widget.onOpenMealPlan!();
                return;
              }
              if (i != 0) setState(() => _selectedNav = i);
            },
            child: _NavItem(icon: items[i].$1, label: items[i].$2, selected: _selectedNav == i),
          ),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w600, color: _muted));
}

class _Meal {
  final String name;
  final String type;
  final String status;
  final Color dotColor;

  const _Meal(this.name, this.type, this.status, this.dotColor);
}

class _HomeData {
  final OnboardingProfile? profile;
  final List<String> exclusions;
  final List<Map<String, dynamic>> meals;

  const _HomeData(this.profile, this.exclusions, this.meals);
}

class _ProfileChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProfileChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEADCCB)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: const Color(0xFF9C6B3F)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF55483D))),
        ]),
      );
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String value;
  final String label;

  const _StatCard({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.fromLTRB(8, 8, 5, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFECEBE9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCD9D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF26211E))),
          Text(label, maxLines: 2, style: const TextStyle(fontSize: 8.5, height: 1.1, color: Color(0xFF8A837D))),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  final _Meal meal;

  const _MealRow({required this.meal});

  @override
  Widget build(BuildContext context) {
    final statusColor = meal.status == 'Done' ? const Color(0xFF2D9070) : const Color(0xFF8D7A66);
    final statusBackground = meal.status == 'Done' ? const Color(0xFFE5F4ED) : const Color(0xFFF1EDE8);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: meal.dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(meal.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF211C18))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF2EEE8), borderRadius: BorderRadius.circular(9)),
            child: Text(meal.type, style: const TextStyle(fontSize: 8.5, color: Color(0xFF82766A))),
          ),
          const SizedBox(width: 5),
          if (meal.status.isNotEmpty) Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: statusBackground, borderRadius: BorderRadius.circular(9)),
            child: Text(meal.status == 'Done' ? '✓ Done' : meal.status, style: TextStyle(fontSize: 8.5, color: statusColor)),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE4DED6)),
          boxShadow: const [BoxShadow(color: Color(0x0C000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 19)),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(fontSize: 9.5, color: Color(0xFF26211E))),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String icon;
  final String label;
  final bool selected;

  const _NavItem({required this.icon, required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: TextStyle(fontSize: 18, color: selected ? const Color(0xFFF47A2A) : const Color(0xFF6E6259))),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 8.5, color: selected ? const Color(0xFFF47A2A) : const Color(0xFF8A8179))),
        ],
      ),
    );
  }
}
