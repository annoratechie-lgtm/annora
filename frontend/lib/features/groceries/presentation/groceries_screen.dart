import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../meal_plan/data/meal_plan_api.dart';

/// Builds the grocery list for a meal plan. The backend needs the plan's
/// ingredients saved first (POST /ingredients), then aggregates them into the
/// list (POST /grocery-list). Both calls replace earlier rows, so retrying is safe.
Future<void> makeGroceryList(MealPlanApi api, String planId) async {
  await api.generateIngredients(planId);
  await api.generateGroceryList(planId);
}

/// One saved grocery item, as returned by GET /meal-plans/{id}/grocery-list.
class GroceryItem {
  final String name;
  final double quantity;
  final String unit;
  final String category;
  final bool purchased;
  final bool urgent;

  const GroceryItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.purchased,
    required this.urgent,
  });

  factory GroceryItem.fromMap(Map<String, dynamic> m) => GroceryItem(
        name: (m['ingredient_name'] ?? '').toString(),
        quantity: double.tryParse(
                '${m['purchase_quantity'] ?? m['required_quantity'] ?? 0}') ??
            0,
        unit: (m['unit'] ?? '').toString(),
        category: _titleCase((m['category'] ?? '').toString().trim().isEmpty
            ? 'Other'
            : m['category'].toString()),
        purchased: m['is_purchased'] == true,
        urgent: m['is_urgent'] == true,
      );

  static String _titleCase(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

List<GroceryItem> parseGroceryItems(Map<String, dynamic> response) {
  final rows = response['items'];
  if (rows is! List) return const [];
  return rows
      .whereType<Map>()
      .map((r) => GroceryItem.fromMap(Map<String, dynamic>.from(r)))
      .toList();
}

String formatQuantity(double value, String unit) {
  final number = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
  return unit.isEmpty ? number : '$number $unit';
}

const _bg = AppColors.background;
const _card = Color(0xFF1E1815);
const _line = Color(0x14FFFFFF);

class GroceriesScreen extends StatefulWidget {
  final MealPlanApi api;
  final bool isActive;
  final VoidCallback? onOpenHome;

  const GroceriesScreen(
      {super.key, required this.api, this.isActive = true, this.onOpenHome});

  @override
  State<GroceriesScreen> createState() => _GroceriesScreenState();
}

class _GroceriesScreenState extends State<GroceriesScreen> {
  late Future<_GroceryState> _state = _load();
  bool _building = false;

  @override
  void didUpdateWidget(covariant GroceriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive)
      setState(() => _state = _load());
  }

  Future<_GroceryState> _load() async {
    final Map<String, dynamic> plan;
    try {
      plan = await widget.api.fetchMealPlan();
    } on MealPlanApiException catch (e) {
      if (e.statusCode == 404) return const _GroceryState(planId: null);
      rethrow;
    }
    final info = plan['meal_plan'];
    final planId = info is Map ? info['id']?.toString() : null;
    if (planId == null) return const _GroceryState(planId: null);
    try {
      final list = await widget.api.fetchGroceryList(planId);
      return _GroceryState(planId: planId, items: parseGroceryItems(list));
    } on MealPlanApiException catch (e) {
      if (e.statusCode == 404) return _GroceryState(planId: planId);
      rethrow;
    }
  }

  Future<void> _build(String planId) async {
    if (_building) return;
    setState(() => _building = true);
    try {
      await makeGroceryList(widget.api, planId);
      if (mounted) setState(() => _state = _load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Couldn't make the grocery list: $e")));
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: FutureBuilder<_GroceryState>(
              future: _state,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.orange));
                }
                if (snap.hasError) {
                  return _Message(
                    title: "Couldn't load groceries",
                    body: '${snap.error}',
                    action: 'Try again',
                    onAction: () => setState(() => _state = _load()),
                  );
                }
                final state = snap.data!;
                if (state.planId == null) {
                  return _Message(
                    title: 'Plan your week first',
                    body: 'Your grocery list is built from your meal plan.',
                    action: 'Go to Home',
                    onAction: widget.onOpenHome,
                  );
                }
                if (state.items == null) {
                  return _Message(
                    title: 'No grocery list yet',
                    body: "Turn this week's plan into one shopping list.",
                    action: _building ? null : 'Make grocery list',
                    busy: _building,
                    onAction: () => _build(state.planId!),
                  );
                }
                return _buildList(state);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(_GroceryState state) {
    final items = state.items!;
    final byCategory = <String, List<GroceryItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }
    final urgent = items.where((i) => i.urgent).length;
    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: () async => setState(() => _state = _load()),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text('Groceries',
                  style: AppTheme.displayFont.copyWith(
                      fontSize: 27, color: AppColors.textPrimary, height: 1.1)),
            ),
            TextButton(
              onPressed: _building ? null : () => _build(state.planId!),
              child: Text(_building ? 'Rebuilding…' : 'Rebuild',
                  style: const TextStyle(
                      color: AppColors.orange, fontWeight: FontWeight.w600)),
            ),
          ]),
          Text(
            '${items.length} items${urgent > 0 ? ' · $urgent urgent' : ''} · for this week\'s plan',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          for (final entry in byCategory.entries) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8, top: 6),
              child: Text(entry.key.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600)),
            ),
            Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _line),
              ),
              child: Column(children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, color: _line, indent: 16, endIndent: 16),
                  _ItemRow(item: entry.value[i]),
                ],
              ]),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _GroceryState {
  final String? planId;
  final List<GroceryItem>? items; // null = no list yet

  const _GroceryState({required this.planId, this.items});
}

class _ItemRow extends StatelessWidget {
  final GroceryItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Expanded(
          child: Text(item.name,
              style: TextStyle(
                color: item.purchased
                    ? AppColors.textFaint
                    : AppColors.textPrimary,
                decoration: item.purchased ? TextDecoration.lineThrough : null,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              )),
        ),
        if (item.urgent)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0x26FF7A3D),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('Urgent',
                style: TextStyle(
                    color: AppColors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        Text(formatQuantity(item.quantity, item.unit),
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  const _Message(
      {required this.title,
      required this.body,
      this.action,
      this.onAction,
      this.busy = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: const Color(0x24FF7A3D),
              borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.shopping_bag_outlined,
              color: AppColors.orange, size: 30),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: AppTheme.displayFont.copyWith(
                fontSize: 24, color: AppColors.textPrimary, height: 1.1)),
        const SizedBox(height: 6),
        Text(body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
        const SizedBox(height: 20),
        if (busy)
          const CircularProgressIndicator(color: AppColors.orange)
        else if (action != null && onAction != null)
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26)),
              ),
              child: Text(action!,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
      ]),
    );
  }
}
