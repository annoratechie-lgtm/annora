import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/annora_ui.dart';
import '../../meal_plan/data/meal_plan_api.dart';
import '../../meal_plan/data/plan_models.dart';
import '../../onboarding/data/onboarding_repository.dart';

/// Builds the grocery list for a meal plan. The backend needs the plan's
/// ingredients saved first (POST /ingredients), then aggregates them into the
/// list (POST /grocery-list). Both replace earlier rows, so retrying is safe;
/// the backend keeps items the user had already ticked.
Future<void> makeGroceryList(MealPlanApi api, String planId) async {
  await api.generateIngredients(planId);
  await api.generateGroceryList(planId);
}

/// Aisle order on screen; Pantry is shown separately as "Pantry check".
const groceryCategoryOrder = [
  'Vegetables & herbs',
  'Fruits',
  'Dairy',
  'Grains & flours',
  'Dals & pulses',
  'Other'
];
const pantryCategory = 'Pantry';

/// One saved grocery item, as returned by GET /meal-plans/{id}/grocery-list.
class GroceryItem {
  final String id;
  final String name;
  final double quantity;
  final String unit;
  final String category;
  final bool purchased;
  final bool urgent;

  const GroceryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.purchased,
    required this.urgent,
  });

  factory GroceryItem.fromMap(Map<String, dynamic> m) {
    final category = (m['category'] ?? '').toString().trim();
    return GroceryItem(
      id: (m['id'] ?? '').toString(),
      name: (m['ingredient_name'] ?? '').toString(),
      quantity: double.tryParse(
              '${m['purchase_quantity'] ?? m['required_quantity'] ?? 0}') ??
          0,
      unit: (m['unit'] ?? '').toString(),
      category: category.isEmpty ? 'Other' : category,
      purchased: m['is_purchased'] == true,
      urgent: m['is_urgent'] == true,
    );
  }

  GroceryItem copyWith({bool? purchased}) => GroceryItem(
        id: id,
        name: name,
        quantity: quantity,
        unit: unit,
        category: category,
        purchased: purchased ?? this.purchased,
        urgent: urgent,
      );

  bool get isPantry => category == pantryCategory;
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
  if (unit.isEmpty || unit == 'piece') return number;
  return '$number $unit';
}

/// Known aisles first, then any other category present (items are never hidden).
List<String> categoriesFor(Iterable<GroceryItem> items) => [
      ...groceryCategoryOrder,
      ...{
        for (final i in items)
          if (!i.isPantry && !groceryCategoryOrder.contains(i.category))
            i.category
      },
    ];

/// Plain-text list for sharing (what's left to buy, by aisle).
String shareText(List<GroceryItem> items, String heading) {
  final buffer = StringBuffer('$heading\n');
  for (final category in categoriesFor(items)) {
    final left =
        items.where((i) => i.category == category && !i.purchased).toList();
    if (left.isEmpty) continue;
    buffer.writeln('\n${category.toUpperCase()}');
    for (final i in left) {
      buffer.writeln('- ${i.name}: ${formatQuantity(i.quantity, i.unit)}');
    }
  }
  final pantry = items
      .where((i) => i.isPantry && !i.purchased)
      .map((i) => i.name)
      .toList();
  if (pantry.isNotEmpty) buffer.writeln('\nCHECK PANTRY\n${pantry.join(', ')}');
  return buffer.toString().trimRight();
}

class GroceriesScreen extends StatefulWidget {
  final MealPlanApi api;
  final OnboardingRepository? repository;
  final bool isActive;
  final VoidCallback? onOpenHome;

  const GroceriesScreen(
      {super.key,
      required this.api,
      this.repository,
      this.isActive = true,
      this.onOpenHome});

  @override
  State<GroceriesScreen> createState() => _GroceriesScreenState();
}

class _GroceriesScreenState extends State<GroceriesScreen> {
  late Future<void> _loading = _load();
  String? _planId;
  List<DateTime> _days = const [];
  int? _household;
  List<GroceryItem>? _items; // null = no list yet
  bool _building = false;
  bool _confirmRebuild = false;
  final _saving = <String>{};

  @override
  void didUpdateWidget(covariant GroceriesScreen oldWidget) {
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
    Map<String, dynamic> plan;
    try {
      plan = await widget.api.fetchMealPlan();
    } on MealPlanApiException catch (e) {
      if (e.statusCode == 404) {
        _planId = null;
        _items = null;
        return;
      }
      rethrow;
    }
    final parsed = parsePlan(plan);
    _planId = parsed.planId;
    _days = parsed.days;
    if (_planId == null) return;
    try {
      _items = parseGroceryItems(await widget.api.fetchGroceryList(_planId!));
    } on MealPlanApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      _items = null;
    }
  }

  Future<void> _build() async {
    if (_building || _planId == null) return;
    setState(() {
      _building = true;
      _confirmRebuild = false;
    });
    try {
      await makeGroceryList(widget.api, _planId!);
      await _load();
    } catch (e) {
      _snack("Couldn't make the grocery list: $e");
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  /// Optimistic tick: update the screen now, PATCH the backend, undo on failure.
  Future<void> _toggle(GroceryItem item) async {
    if (_planId == null || _saving.contains(item.id)) return;
    final next = !item.purchased;
    setState(() {
      _saving.add(item.id);
      _items = [
        for (final i in _items!)
          i.id == item.id ? i.copyWith(purchased: next) : i
      ];
    });
    try {
      await widget.api.setGroceryItemPurchased(_planId!, item.id, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = [
            for (final i in _items!)
              i.id == item.id ? i.copyWith(purchased: !next) : i
          ]);
      _snack("Couldn't save that. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _saving.remove(item.id));
    }
  }

  Future<void> _share() async {
    final heading =
        'Annora grocery list${_days.isEmpty ? '' : ' (${_range()})'}';
    await Clipboard.setData(
        ClipboardData(text: shareText(_items ?? const [], heading)));
    _snack('List copied. Paste it into WhatsApp or your notes.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _range() {
    if (_days.isEmpty) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final a = _days.first, b = _days.last;
    return a.month == b.month
        ? '${a.day}–${b.day} ${months[b.month - 1]}'
        : '${a.day} ${months[a.month - 1]} – ${b.day} ${months[b.month - 1]}';
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
              title: "Couldn't load groceries",
              body: '${snap.error}',
              action: 'Try again',
              onAction: () => setState(() {
                _loading = _load();
              }),
            );
          }
          if (_planId == null) {
            return EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Plan your week first',
              body: 'Your grocery list is built from your meal plan.',
              action: 'Go to Home',
              onAction: widget.onOpenHome,
            );
          }
          if (_items == null) {
            return EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'No grocery list yet',
              body:
                  "Turn this week's plan into one shopping list${_household != null ? ' for $_household ${_household == 1 ? 'person' : 'people'}' : ''}.",
              action: 'Make grocery list',
              busy: _building,
              onAction: _build,
            );
          }
          return RefreshIndicator(
            color: AppColors.orange,
            onRefresh: () async {
              await _load();
              if (mounted) setState(() {});
            },
            child: _list(),
          );
        },
      ),
    );
  }

  Widget _list() {
    final items = _items!;
    final shopping = items.where((i) => !i.isPantry).toList();
    final pantry = items.where((i) => i.isPantry).toList();
    final done = shopping.where((i) => i.purchased).length;
    final basket = shopping.where((i) => i.purchased).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        PageTitle(
          title: 'Groceries',
          subtitle: [
            if (_days.isNotEmpty) 'For ${_range()}',
            if (_household != null)
              '$_household ${_household == 1 ? 'person' : 'people'}',
          ].join(' · '),
          trailing: GhostButton(label: 'Share list', onTap: _share),
        ),
        const SizedBox(height: 16),
        ACard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('$done of ${shopping.length} bought',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
              Text('${shopping.length - done} left',
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 12.5)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: shopping.isEmpty ? 0 : done / shopping.length,
                minHeight: 6,
                backgroundColor: const Color(0x14FFFFFF),
                color: AppColors.orange,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        for (final category in categoriesFor(shopping))
          ..._section(category, shopping),
        if (basket.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('basket'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 2),
              childrenPadding: EdgeInsets.zero,
              iconColor: AppColors.textMuted,
              collapsedIconColor: AppColors.textMuted,
              title: Text('In your basket (${basket.length})',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5)),
              children: [_itemsCard(basket)],
            ),
          ),
        if (pantry.isNotEmpty) ...[
          const SizedBox(height: 8),
          ACard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: Text('Pantry check',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600)),
                ),
                Text(
                    '${pantry.where((i) => i.purchased).length} of ${pantry.length} at home',
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 12.5)),
              ]),
              const SizedBox(height: 4),
              const Text('Small amounts this week. Tap what you already have.',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final p in pantry) _pantryChip(p)]),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        ACard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Changed your plan?',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 2),
            const Text(
                "Rebuild the list from this week's meals. Ticked items stay ticked.",
                style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
            const SizedBox(height: 12),
            if (_confirmRebuild || _building)
              ConfirmBox(
                message: 'Rebuild the grocery list now?',
                confirmLabel: 'Rebuild',
                busy: _building,
                onConfirm: _build,
                onCancel: () => setState(() => _confirmRebuild = false),
              )
            else
              GhostButton(
                  label: 'Rebuild list',
                  onTap: () => setState(() => _confirmRebuild = true)),
          ]),
        ),
      ],
    );
  }

  List<Widget> _section(String category, List<GroceryItem> shopping) {
    final toBuy =
        shopping.where((i) => i.category == category && !i.purchased).toList();
    if (toBuy.isEmpty) return const [];
    return [
      SectionLabel(category, trailing: '${toBuy.length}'),
      _itemsCard(toBuy),
      const SizedBox(height: 16),
    ];
  }

  Widget _itemsCard(List<GroceryItem> items) => Material(
        color: AnnoraUi.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AnnoraUi.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AnnoraUi.line),
            _ItemRow(item: items[i], onTap: () => _toggle(items[i])),
          ],
        ]),
      );

  Widget _pantryChip(GroceryItem item) {
    final have = item.purchased;
    return Semantics(
      button: true,
      selected: have,
      label: '${item.name}${have ? ', at home' : ''}',
      child: Material(
        color: have ? const Color(0x1F7BC47F) : const Color(0x08FFFFFF),
        shape: StadiumBorder(
            side: BorderSide(
                color: have ? const Color(0x997BC47F) : AnnoraUi.lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _toggle(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 13, 7),
            child: ExcludeSemantics(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(have ? Icons.check_rounded : Icons.add_rounded,
                    size: 15, color: have ? AnnoraUi.ok : AppColors.textFaint),
                const SizedBox(width: 6),
                Text(item.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final GroceryItem item;
  final VoidCallback onTap;
  const _ItemRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = item.purchased;
    return Semantics(
      checked: done,
      button: true,
      label: '${item.name}, ${formatQuantity(item.quantity, item.unit)}',
      child: InkWell(
        key: Key('item-${item.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: ExcludeSemantics(
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: done ? AppColors.orange : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: done ? AppColors.orange : AnnoraUi.lineStrong,
                      width: 1.5),
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.name,
                    style: TextStyle(
                      color: done ? AppColors.textFaint : AppColors.textPrimary,
                      decoration: done ? TextDecoration.lineThrough : null,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    )),
              ),
              Text(formatQuantity(item.quantity, item.unit),
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }
}
