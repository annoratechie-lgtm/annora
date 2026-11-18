import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/annora_ui.dart';
import '../data/meal_plan_api.dart';
import '../data/plan_models.dart';

/// One alternative recipe from GET /meal-plans/meals/{row}/alternatives.
class SwapOption {
  final String code;
  final String name;
  final int? kcal;
  final double? protein;
  final bool kcalUnverified;

  const SwapOption(
      {required this.code,
      required this.name,
      this.kcal,
      this.protein,
      this.kcalUnverified = false});

  static List<SwapOption> listFrom(Map<String, dynamic> response) {
    final rows = response['alternatives'];
    if (rows is! List) return const [];
    return [
      for (final r in rows.whereType<Map>())
        if (r['code'] != null && r['name'] != null)
          SwapOption(
            code: r['code'].toString(),
            name: r['name'].toString(),
            kcal: (r['kcal'] as num?)?.round(),
            protein: (r['protein_g'] as num?)?.toDouble(),
            kcalUnverified: r['kcal_unverified'] == true,
          ),
    ];
  }
}

/// Swap one dish of a meal from the Plan tab (source: app).
/// Completes with true when the plan changed.
Future<bool> showSwapSheet(
  BuildContext context, {
  required MealPlanApi api,
  required String title,
  required List<Dish> dishes,
  VoidCallback? onAskAnnora,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: SwapSheet(
          api: api, title: title, dishes: dishes, onAskAnnora: onAskAnnora),
    ),
  );
  return changed == true;
}

class SwapSheet extends StatefulWidget {
  final MealPlanApi api;
  final String title;
  final List<Dish> dishes;
  final VoidCallback? onAskAnnora;

  const SwapSheet(
      {super.key,
      required this.api,
      required this.title,
      required this.dishes,
      this.onAskAnnora});

  @override
  State<SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<SwapSheet> {
  late Dish _dish = widget.dishes.firstWhere((d) => d.id != null,
      orElse: () => widget.dishes.first);
  String _sort = 'any';
  final _search = TextEditingController();
  List<SwapOption>? _options;
  String? _error;
  SwapOption? _picked;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _dish.id;
    setState(() {
      _options = null;
      _error = null;
      _picked = null;
    });
    if (id == null) {
      setState(() => _error = 'This meal can’t be swapped yet. Pull to refresh your plan.');
      return;
    }
    try {
      final response = await widget.api
          .fetchAlternatives(id, sort: _sort, query: _search.text);
      if (mounted) setState(() => _options = SwapOption.listFrom(response));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _swap() async {
    final picked = _picked, id = _dish.id;
    if (picked == null || id == null) return;
    setState(() => _saving = true);
    try {
      await widget.api.swapMeal(id, picked.code, fromCode: _dish.code);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text('Swapped to ${picked.name}. Grocery list updated.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close, color: AppColors.textMuted),
          ),
        ]),
      ),
      if (widget.dishes.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in widget.dishes)
              ChoiceChip(
                label: Text(d.name, overflow: TextOverflow.ellipsis),
                selected: identical(d, _dish),
                onSelected: (_) {
                  setState(() => _dish = d);
                  _load();
                },
                selectedColor: AnnoraUi.accentSoft,
                backgroundColor: const Color(0x08FFFFFF),
                labelStyle: const TextStyle(color: AppColors.textPrimary),
                side: const BorderSide(color: AnnoraUi.lineStrong),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
        child: Text('Replace ${_dish.name} with:',
            style: const TextStyle(color: AppColors.textMuted)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: 8, children: [
          for (final (value, label) in const [
            ('any', 'Any'),
            ('protein', 'More protein'),
            ('lighter', 'Lighter'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _sort == value,
              onSelected: (_) {
                setState(() => _sort = value);
                _load();
              },
              selectedColor: AnnoraUi.accentSoft,
              backgroundColor: const Color(0x08FFFFFF),
              labelStyle: const TextStyle(color: AppColors.textPrimary),
              side: const BorderSide(color: AnnoraUi.lineStrong),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
        child: TextField(
          key: const Key('swap-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          cursorColor: AppColors.orange,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search a dish, e.g. besan chilla',
            hintStyle: const TextStyle(color: AppColors.textFaint),
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
            isDense: true,
            filled: true,
            fillColor: AnnoraUi.field,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AnnoraUi.line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AnnoraUi.line)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(child: _list()),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SafeArea(
          top: false,
          child: Row(children: [
            if (widget.onAskAnnora != null)
              LinkButton(label: 'Ask Annora instead', onTap: () {
                Navigator.of(context).pop(false);
                widget.onAskAnnora!();
              }),
            const Spacer(),
            PrimaryButton(
              label: _picked == null ? 'Pick a dish' : 'Swap to ${_picked!.name}',
              busy: _saving,
              onTap: _picked == null ? null : _swap,
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _list() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(_error!, style: const TextStyle(color: AnnoraUi.danger)),
      );
    }
    final options = _options;
    if (options == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.orange));
    }
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('No matching dishes fit your diet and foods to avoid here.',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final o in options)
          Material(
            color: identical(o, _picked) ? AnnoraUi.card2 : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              key: ValueKey('swap-${o.code}'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onTap: _saving ? null : () => setState(() => _picked = o),
              leading: Icon(
                  identical(o, _picked)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: AppColors.orange),
              title: Text(o.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  if (o.kcal != null && !o.kcalUnverified) '${fmtInt(o.kcal!)} kcal',
                  if (o.protein != null) '${o.protein!.toStringAsFixed(1)} g protein',
                ].join(' · '),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}
