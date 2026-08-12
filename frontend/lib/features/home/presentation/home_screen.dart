import 'package:flutter/material.dart';

/// Post-onboarding home screen.
///
/// The current meal, spend, pantry and suggestion values are preview data.
/// They will be replaced by the generated 7-day plan and pantry/grocery data
/// once those services are available.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedNav = 0;

  static const _background = Color(0xFFFAF7F1);
  static const _text = Color(0xFF171411);
  static const _muted = Color(0xFF7B746D);
  static const _orange = Color(0xFFF47A2A);
  static const _green = Color(0xFF4EB68B);
  static const _blue = Color(0xFF5D92D8);
  static const _purple = Color(0xFF8B5BEA);
  static const _border = Color(0xFFE8E1D8);

  static const _meals = [
    _Meal('Masala Oats + Chai', 'Breakfast', 'Done', _orange),
    _Meal('Dal Tadka + Roti', 'Lunch', 'Soon', _green),
    _Meal('Palak Paneer + Rice', 'Dinner', 'Upcoming', _blue),
  ];

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
                    _buildHeader(),
                    const SizedBox(height: 14),
                    _buildStats(),
                    const SizedBox(height: 14),
                    _buildExpiryBanner(),
                    const SizedBox(height: 18),
                    _sectionLabel("TODAY'S MEALS"),
                    const SizedBox(height: 8),
                    _buildMealsCard(),
                    const SizedBox(height: 18),
                    _sectionLabel('QUICK ACTIONS'),
                    const SizedBox(height: 8),
                    _buildQuickActions(),
                    const SizedBox(height: 18),
                    _sectionLabel('✦ ANNORA SUGGESTS'),
                    const SizedBox(height: 8),
                    _buildSuggestion(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Good morning ☀️ Sunday, April 5',
          style: TextStyle(fontSize: 11, color: _muted),
        ),
        const SizedBox(height: 2),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: _text,
            ),
            children: [
              TextSpan(text: "Priya's "),
              TextSpan(text: 'Kitchen', style: TextStyle(color: _orange)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: const [
        Expanded(child: _StatCard(icon: '🍽️', value: '22/30', label: 'Days planned')),
        SizedBox(width: 7),
        Expanded(child: _StatCard(icon: '🪙', value: '₹4.2K', label: 'Spent of ₹6K')),
        SizedBox(width: 7),
        Expanded(child: _StatCard(icon: '♻️', value: '2.1kg', label: 'Waste saved')),
        SizedBox(width: 7),
        Expanded(child: _StatCard(icon: '🏆', value: '78%', label: 'Nutrition\nscore')),
      ],
    );
  }

  Widget _buildExpiryBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFFFFF1D9),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Milk & Dal Toor critically low · 2 items expiring soon',
              style: TextStyle(fontSize: 11, color: Color(0xFFB96A14)),
            ),
          ),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('View →', style: TextStyle(fontSize: 11, color: _orange)),
          ),
        ],
      ),
    );
  }

  Widget _buildMealsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < _meals.length; i++) ...[
            _MealRow(meal: _meals[i]),
            if (i != _meals.length - 1)
              const Divider(height: 1, indent: 14, endIndent: 14, color: _border),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    const actions = [
      ('🗓️', 'Meal Plan'),
      ('🛒', 'Shop'),
      ('📦', 'Pantry'),
      ('📊', 'Analytics'),
    ];

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          Expanded(
            child: _ActionCard(icon: actions[i].$1, label: actions[i].$2, onTap: () {}),
          ),
          if (i != actions.length - 1) const SizedBox(width: 7),
        ],
      ],
    );
  }

  Widget _buildSuggestion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F1FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _purple),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🧑‍🍳 Based on your pantry', style: TextStyle(fontSize: 11, color: _purple)),
          const SizedBox(height: 6),
          const Text(
            "You have spinach expiring in 2 days. I've moved Palak\nDal to tomorrow's lunch to use it up.",
            style: TextStyle(fontSize: 11.5, height: 1.35, color: _text),
          ),
          const SizedBox(height: 7),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(100, 20),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            child: const Text('View meal plan →', style: TextStyle(fontSize: 11, color: _purple)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    const items = [
      ('⌂', 'Home'),
      ('▦', 'Plan'),
      ('🛒', 'Shop'),
      ('📦', 'Pantry'),
      ('♟', 'Profile'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.only(top: 7, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            GestureDetector(
              onTap: () => setState(() => _selectedNav = i),
              child: _NavItem(
                icon: items[i].$1,
                label: items[i].$2,
                selected: _selectedNav == i,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
        color: _muted,
      ),
    );
  }
}

class _Meal {
  final String name;
  final String type;
  final String status;
  final Color dotColor;

  const _Meal(this.name, this.type, this.status, this.dotColor);
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
          Container(
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
