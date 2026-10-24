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
  bool _generating = false;
  bool _generatingPantry = false;
  late Future<Map<String, dynamic>> _future;
  final Map<String, Future<Map<String, dynamic>>> _ingredientsByPlan = {};

  @override
  void initState() {
    super.initState();
    _future = _fetchMealPlanWithRecipeNames();
  }

  void _reload() {
    setState(() {
      _ingredientsByPlan.clear();
      _future = _fetchMealPlanWithRecipeNames();
    });
  }

  Future<Map<String, dynamic>> _fetchMealPlanWithRecipeNames() async {
    final result = await widget.api.fetchMealPlan();
    final rawMeals = result['meals'];
    if (rawMeals is List) {
      result['meals'] = await _withRecipeNames(
        rawMeals.whereType<Map>().map((meal) => Map<String, dynamic>.from(meal)).toList(),
      );
    }
    return result;
  }

  String? _recipeNameFromCode(String value) {
    final match = RegExp(r'^(.*)-([A-Z]{2,}\d+)$').firstMatch(value.trim());
    return match?.group(1)?.trim();
  }

  Future<List<Map<String, dynamic>>> _withRecipeNames(
    List<Map<String, dynamic>> meals,
  ) async {
    return meals.map((meal) {
      final rawCode = meal['source_recipe_code']?.toString();
      final name = meal['name']?.toString();
      final embeddedName = rawCode == null ? null : _recipeNameFromCode(rawCode);
      if ((name == null || name.isEmpty || name == 'NA') && embeddedName != null) {
        return {...meal, 'name': embeddedName};
      }
      return meal;
    }).toList();
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final result = await widget.api.generateMealPlan();
      if (!mounted) return;
      final meals = await _withRecipeNames(
        _flattenGeneratedPlan(result['plan']),
      );
      if (!mounted) return;
      setState(() {
        _future = Future.value({
          'meal_plan': {
            'id': result['meal_id'],
            'status': result['status'],
          },
          'meals': meals,
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your 7-day meal plan is ready.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  List<Map<String, dynamic>> _flattenGeneratedPlan(dynamic rawPlan) {
    if (rawPlan is! Map) return const [];
    final rows = <Map<String, dynamic>>[];
    for (final entry in rawPlan.entries) {
      final date = entry.key.toString();
      final meals = entry.value;
      if (meals is! Map) continue;
      for (final type in ['breakfast', 'lunch', 'dinner']) {
        final raw = meals[type];
        String? name;
        String? recipeCode;
        if (raw is String) {
          final parts = raw.split('-');
          if (parts.length > 1) {
            name = parts.first.trim();
            recipeCode = parts.sublist(1).join('-').trim();
          } else {
            name = 'NA';
            recipeCode = raw.trim();
          }
        } else if (raw is List && raw.isNotEmpty) {
          final value = raw.first?.toString() ?? '';
          final parts = value.split('-');
          if (parts.length > 1) {
            name = parts.first.trim();
            recipeCode = parts.sublist(1).join('-').trim();
          } else {
            name = 'NA';
            recipeCode = value.trim();
          }
        }
        if (name == null || name.isEmpty) continue;
        rows.add({
          'meal_date': date,
          'meal_type': type,
          'name': name,
          'source_recipe_code': recipeCode,
          'status': 'planned',
          'description': null,
          'nutrition': <String, dynamic>{},
        });
      }
    }
    rows.sort((a, b) {
      final dateCompare = a['meal_date'].toString().compareTo(b['meal_date'].toString());
      if (dateCompare != 0) return dateCompare;
      return a['meal_type'].toString().compareTo(b['meal_type'].toString());
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done || _generating) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(
                message: snapshot.error.toString(),
                onRetry: _reload,
                actionLabel: 'Generate plan',
                onAction: _generate,
              );
            }
            return _buildContent(snapshot.data ?? const <String, dynamic>{});
          },
        ),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final plan = Map<String, dynamic>.from(data['meal_plan'] ?? {});
    final rawMeals = data['meals'] as List? ?? const [];
    final meals = rawMeals
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final dates = meals
        .map((e) => e['meal_date']?.toString())
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    if (dates.isEmpty) {
      return _ErrorState(
        message: 'No meals are available for this plan yet.',
        onRetry: _reload,
        actionLabel: 'Generate plan',
        onAction: _generate,
      );
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
                  _buildNutritionSummary(dayMeals),
                ] else if (_selectedTab == 1)
                  _buildNutritionTab(dayMeals)
                else if (_selectedTab == 2)
                  _buildPantryTab(
                    plan['id']?.toString() ?? plan['meal_id']?.toString(),
                    selectedDate,
                  )
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
    final savedName = meal['name']?.toString();
    final recipeCode = meal['source_recipe_code']?.toString();
    final resolvedRecipeName = recipeCode == null ? null : _recipeNameFromCode(recipeCode);
    final name = savedName == null || savedName.isEmpty || savedName == 'NA'
        ? (resolvedRecipeName ?? 'Meal')
        : savedName;
    final description = meal['description']?.toString();
    final icon = type == 'breakfast' ? '🌞' : type == 'lunch' ? '🍲' : type == 'dinner' ? '🌙' : '🍽️';
    final color = type == 'breakfast' ? _orange : type == 'lunch' ? _green : _blue;
    final status = meal['status']?.toString() ?? 'planned';
    final statusLabel = status == 'cooked' ? '✓ Cooked' : status == 'skipped' ? 'Skipped' : 'Planned';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4))]),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('$icon ${type.toUpperCase()}', style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: color, fontWeight: FontWeight.w600)),
            const Spacer(),
            _pill(statusLabel, status == 'cooked' ? const Color(0xFFE5F4ED) : const Color(0xFFFFF1D9), status == 'cooked' ? const Color(0xFF2D9070) : const Color(0xFFB96A14)),
          ]),
          const Divider(height: 18, color: _border),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withOpacity(.18), borderRadius: BorderRadius.circular(14)), child: Center(child: Text(icon, style: const TextStyle(fontSize: 24)))),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _text)),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 10.5, color: _muted, height: 1.3)),
              ],
            ])),
          ]),
        ]),
      ),
    );
  }

  Widget _buildNutritionSummary(List<Map<String, dynamic>> meals) {
    final hasNutrition = meals.any((meal) {
      final nutrition = meal['nutrition'];
      return nutrition is Map && nutrition.isNotEmpty;
    });
    return _simpleCard(
      '📊 Today\'s nutrition summary',
      hasNutrition
          ? 'Nutrition data is available for this day.'
          : 'Nutrition values are not populated by the current meal-planning API yet.',
    );
  }

  Widget _buildNutritionTab(List<Map<String, dynamic>> meals) => _buildNutritionSummary(meals);

  Widget _buildPantryTab(String? planId, String selectedDate) {
    if (planId == null || planId.isEmpty) {
      return _simpleCard('🌿 Ingredients for the day', 'No meal plan is available.');
    }
    final future = _ingredientsByPlan.putIfAbsent(
      planId,
      () => widget.api.fetchIngredients(planId),
    );
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _simpleCard(
            '🌿 Ingredients for the day',
            'Could not load ingredients: ${snapshot.error}',
          );
        }
        final rawMeals = snapshot.data?['meals'];
        final dayMeals = rawMeals is List
            ? rawMeals.whereType<Map>().where(
                (meal) => meal['meal_date']?.toString() == selectedDate,
              ).toList()
            : const [];
        final items = <Map<String, dynamic>>[];
        for (final meal in dayMeals) {
          final ingredients = meal['ingredients'];
          if (ingredients is List) {
            items.addAll(ingredients.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ));
          }
        }
        if (items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🌿 Ingredients for the day', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _text)),
                const SizedBox(height: 7),
                const Text('No ingredients are saved for this day yet. Create the ingredient list for this meal plan to view them here.', style: TextStyle(fontSize: 12, color: _muted)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _generatingPantry ? null : () => _generatePantryList(planId),
                    icon: _generatingPantry
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 17),
                    label: Text(_generatingPantry ? 'Creating list…' : 'Create ingredient list'),
                    style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
        final uniqueItems = <String, Map<String, dynamic>>{};
        for (final item in items) {
          final name = (item['food_name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final unit = item['unit']?.toString().trim() ?? '';
          final key = '${name.toLowerCase()}|${unit.toLowerCase()}';
          final previous = uniqueItems[key];
          if (previous == null) {
            uniqueItems[key] = item;
          } else {
            final oldAmount = double.tryParse(previous['amount']?.toString() ?? '');
            final newAmount = double.tryParse(item['amount']?.toString() ?? '');
            if (oldAmount != null && newAmount != null &&
                unit == (item['unit']?.toString().trim() ?? '')) {
              uniqueItems[key] = {
                ...previous,
                'amount': oldAmount + newAmount,
              };
            }
          }
        }
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [
              BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ingredients for the day', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _text)),
              const SizedBox(height: 4),
              Text('${uniqueItems.length} ingredients across ${dayMeals.length} meals', style: const TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 12),
              for (final item in uniqueItems.values) ...[
                const Divider(height: 1, color: _border),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 7, color: _green),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item['food_name']?.toString() ?? 'Ingredient', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _text))),
                      Text(_formatIngredientAmount(item['amount'], item['unit']), style: const TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _generatePantryList(String planId) async {
    setState(() => _generatingPantry = true);
    try {
      await widget.api.generateIngredients(planId);
      _ingredientsByPlan.remove(planId);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create ingredient list: $error')),
      );
    } finally {
      if (mounted) setState(() => _generatingPantry = false);
    }
  }

  String _formatIngredientAmount(dynamic amount, dynamic unit) {
    final amountText = amount?.toString() ?? '';
    final unitText = unit?.toString() ?? '';
    return [amountText, unitText].where((part) => part.trim().isNotEmpty).join(' ');
  }

  Widget _buildAssistTab() => _simpleCard('⚡ Annora Assist', 'Meal swaps and AI assistance are not part of the current meal-planning API contract.');

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
  final String actionLabel;
  final VoidCallback onAction;

  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🍽️', style: TextStyle(fontSize: 38)),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6E6259))),
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
