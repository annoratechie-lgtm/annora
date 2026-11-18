// Meal plan models shared by Home and Plan.

/// 15000 -> "15,000" (Indian grouping).
String fmtInt(num value) {
  final s = value.round().toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}

class Dish {
  /// meal_plan row id (used for swaps).
  final String? id;
  final String? code;
  final String name;
  final String? unit;
  final double? kcal;
  final double? protein;
  final double? carbs;

  /// 'planner' | 'app_swap' | 'annora_chat': who put this dish in the plan.
  final String origin;

  const Dish(
      {this.id,
      this.code,
      required this.name,
      this.unit,
      this.kcal,
      this.protein,
      this.carbs,
      this.origin = 'planner'});

  bool get changedByAnnora => origin == 'annora_chat';

  /// 64 recipes claim >1,500 kcal per serving while protein + carbs explain
  /// <600 kcal; their calories are left out of totals until the data is fixed.
  bool get caloriesUnverified =>
      kcal == null ||
      (kcal! > 1500 && (protein ?? 0) * 4 + (carbs ?? 0) * 4 < 600);
}

class DayTotals {
  final double kcal;
  final double protein;
  final double carbs;
  final int unverified;
  const DayTotals(this.kcal, this.protein, this.carbs, this.unverified);
}

class ParsedPlan {
  final String? planId;
  final List<DateTime> days;
  final Map<DateTime, Map<String, List<Dish>>> menu;

  const ParsedPlan(
      {required this.planId, required this.days, required this.menu});

  int get dishCount => menu.values
      .fold(0, (n, day) => n + day.values.fold(0, (m, d) => m + d.length));

  DayTotals totalsFor(DateTime day) {
    var kcal = 0.0, protein = 0.0, carbs = 0.0;
    var unverified = 0;
    for (final dishes in (menu[day] ?? const {}).values) {
      for (final d in dishes) {
        protein += d.protein ?? 0;
        carbs += d.carbs ?? 0;
        if (d.caloriesUnverified) {
          unverified++;
        } else {
          kcal += d.kcal!;
        }
      }
    }
    return DayTotals(kcal, protein, carbs, unverified);
  }
}

/// Parses GET /meal-plans/{user_id}: {meal_plan: {id, start_date, end_date}, meals: [...]}.
ParsedPlan parsePlan(Map<String, dynamic> response) {
  final info = response['meal_plan'];
  final planId = info is Map ? info['id']?.toString() : null;
  DateTime? parse(Object? v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  final start = info is Map ? parse(info['start_date']) : null;
  final end = info is Map ? parse(info['end_date']) : null;
  final menu = <DateTime, Map<String, List<Dish>>>{};
  final rows = response['meals'];
  if (rows is List) {
    for (final row in rows.whereType<Map>()) {
      final date = parse(row['meal_date']);
      final type = row['meal_type']?.toString().toLowerCase();
      if (date == null || type == null) continue;
      final rawName = row['name']?.toString().trim();
      final name = rawName == null || rawName.isEmpty || rawName == 'NA'
          ? (row['source_recipe_code']?.toString() ?? 'Meal')
          : rawName;
      final n = row['nutrition'];
      double? num(String key) =>
          n is Map ? double.tryParse('${n[key] ?? ''}') : null;
      menu.putIfAbsent(date, () => {}).putIfAbsent(type, () => []).add(Dish(
            id: row['id']?.toString(),
            code: row['source_recipe_code']?.toString(),
            origin: row['origin']?.toString() ?? 'planner',
            name: name,
            unit: n is Map ? n['servings_unit']?.toString() : null,
            kcal: num('unit_serving_energy_kcal'),
            protein: num('unit_serving_protein_g'),
            carbs: num('unit_serving_carb_g'),
          ));
    }
  }
  final days = <DateTime>[];
  if (start != null && end != null && !end.isBefore(start)) {
    for (var d = start;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
  } else {
    days.addAll(menu.keys.toList()..sort());
  }
  return ParsedPlan(planId: planId, days: days, menu: menu);
}
