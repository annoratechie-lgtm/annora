import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/user_profile_api.dart';
import '../../onboarding/data/onboarding_repository.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfileApi api;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenMealPlan;
  final bool isActive;

  const ProfileScreen({
    super.key,
    required this.api,
    this.onOpenHome,
    this.onOpenMealPlan,
    this.isActive = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _background = Color(0xFFFAF7F1);
  static const _text = Color(0xFF211C18);
  static const _muted = Color(0xFF7B746D);
  static const _orange = Color(0xFFF47A2A);
  static const _green = Color(0xFF4EB68B);
  static const _border = Color(0xFFE8E1D8);

  late Future<_ProfileData> _profileFuture;
  bool _savingNotifications = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      setState(() => _profileFuture = _loadProfile());
    }
  }

  Future<_ProfileData> _loadProfile() async {
    final repository = OnboardingRepository();
    final results = await Future.wait<Object?>([
      repository.fetchProfile(),
      repository.fetchDietaryExclusions(),
      widget.api.fetchProfile(),
    ]);
    return _ProfileData(
      results[0] as OnboardingProfile?,
      results[1] as List<String>,
      results[2] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> get _metadata {
    final user = Supabase.instance.client.auth.currentUser;
    return Map<String, dynamic>.from(user?.userMetadata ?? const {});
  }

  String get _displayName {
    final metadata = _metadata;
    final name =
        (metadata['full_name'] ?? metadata['name'] ?? metadata['display_name'])
            ?.toString()
            .trim();
    if (name?.isNotEmpty == true) return name!;
    return Supabase.instance.client.auth.currentUser?.email?.split('@').first ??
        'Annora member';
  }

  Future<void> _updateMetadata(Map<String, dynamic> updates) async {
    final metadata = _metadata..addAll(updates);
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(data: metadata),
    );
  }

  Future<void> _editName(String currentName, String? currentPhone) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: _text),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    await _runAction(
      () async {
        await widget.api.syncProfile(name: name, phone: currentPhone);
        if (mounted) setState(() => _profileFuture = _loadProfile());
      },
      successMessage: 'Name updated.',
    );
  }

  Future<void> _editPhone(String currentName, String? currentPhone) async {
    final controller = TextEditingController(text: currentPhone ?? '');
    final phone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Contact phone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: _text),
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+91 98765 43210',
            helperText: 'Optional and not verified.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (controller.text.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Remove'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (phone == null || !mounted) return;

    final normalizedPhone = phone.trim();
    if (normalizedPhone.isNotEmpty &&
        !RegExp(r'^\+?[0-9\s()-]{7,20}$').hasMatch(normalizedPhone)) {
      _showMessage('Enter a valid phone number.');
      return;
    }
    await _runAction(
      () async {
        final updatedPhone = normalizedPhone.isEmpty ? null : normalizedPhone;
        await widget.api.syncProfile(name: currentName, phone: updatedPhone);
        if (mounted) setState(() => _profileFuture = _loadProfile());
      },
      successMessage: normalizedPhone.isEmpty
          ? 'Phone number removed.'
          : 'Phone number updated.',
    );
  }

  Future<void> _editFoodProfile(_ProfileData data) async {
    final profile = data.profile;
    if (profile == null) {
      _showMessage('Your onboarding profile is not available.');
      return;
    }
    final edits = await showModalBottomSheet<_ProfileEdits>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _background,
      builder: (context) => _ProfileEditSheet(
        profile: profile,
        exclusions: data.exclusions,
      ),
    );
    if (edits == null || !mounted) return;

    await _runAction(() async {
      await OnboardingRepository().updateProfile(
        familySize: edits.familySize,
        monthlyBudget: edits.monthlyBudget,
        dietaryPreference: edits.dietaryPreference,
        dietaryGoals: edits.dietaryGoals,
        exclusions: edits.exclusions,
      );
      if (mounted) setState(() => _profileFuture = _loadProfile());
    }, successMessage: 'Your preferences were updated.');
  }

  Future<void> _setNotificationPreference(String key, bool value) async {
    if (_savingNotifications) return;
    setState(() => _savingNotifications = true);
    try {
      final preferences = Map<String, dynamic>.from(
        _metadata['notification_preferences'] is Map
            ? _metadata['notification_preferences'] as Map
            : const {},
      );
      preferences[key] = value;
      await _updateMetadata({'notification_preferences': preferences});
      if (mounted) {
        _showMessage('Notification preference saved for future use.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Could not save notification preference: $error');
      }
    } finally {
      if (mounted) setState(() => _savingNotifications = false);
    }
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (mounted) _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showMessage('Could not save changes: $error');
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _signingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      if (mounted) {
        _showMessage('Could not sign out: $error');
        setState(() => _signingOut = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'No email available';
    final rawPreferences = _metadata['notification_preferences'];
    final notificationPreferences = rawPreferences is Map
        ? Map<String, dynamic>.from(rawPreferences)
        : <String, dynamic>{};

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<_ProfileData>(
                future: _profileFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done ||
                      _signingOut) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _LoadError(
                      message: snapshot.error.toString(),
                      onRetry: () =>
                          setState(() => _profileFuture = _loadProfile()),
                    );
                  }
                  final data = snapshot.data ??
                      const _ProfileData(null, [], <String, dynamic>{});
                  final profileName =
                      data.userProfile['name']?.toString().trim();
                  final profilePhone =
                      data.userProfile['phone']?.toString().trim();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    children: [
                      const Text(
                        'YOUR PROFILE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildIdentityCard(
                        email: email,
                        name: profileName?.isNotEmpty == true
                            ? profileName!
                            : _displayName,
                        phone: profilePhone?.isNotEmpty == true
                            ? profilePhone
                            : null,
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle('YOUR KITCHEN'),
                      const SizedBox(height: 8),
                      _buildKitchenCard(data),
                      const SizedBox(height: 22),
                      _sectionTitle('NOTIFICATIONS'),
                      const SizedBox(height: 8),
                      _buildNotificationsCard(notificationPreferences),
                      const SizedBox(height: 22),
                      _sectionTitle('ACCOUNT'),
                      const SizedBox(height: 8),
                      _buildAccountCard(email),
                      const SizedBox(height: 22),
                      _sectionTitle('HELP & SUPPORT'),
                      const SizedBox(height: 8),
                      _buildHelpSupportCard(),
                    ],
                  );
                },
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityCard({
    required String email,
    required String name,
    required String? phone,
  }) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFFFFF0E2),
                    child: Text(
                      initials.isEmpty ? 'A' : initials,
                      style: const TextStyle(
                        color: _orange,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        size: 15,
                        color: _muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(email,
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _editName(name, phone),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(height: 1, color: _border),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.phone_outlined, color: _muted, size: 19),
            title: Text(
              phone?.isNotEmpty == true ? phone! : 'Add a phone number',
              style: const TextStyle(fontSize: 12, color: _text),
            ),
            subtitle: const Text(
              'Optional · not verified',
              style: TextStyle(fontSize: 10, color: _muted),
            ),
            trailing: const Icon(Icons.chevron_right, color: _muted),
            onTap: () => _editPhone(name, phone),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  _showMessage('Profile photo upload is coming soon.'),
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: const Text('Add profile photo · coming soon'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKitchenCard(_ProfileData data) {
    final profile = data.profile;
    if (profile == null) {
      return _card(
        child: const Text(
          'Household preferences are not available yet.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      );
    }
    final goals = profile.dietaryGoals
        .where((goal) => goal != 'no_preference')
        .map(_prettyLabel)
        .toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(
            Icons.people_outline,
            'Household',
            '${profile.familySize} ${profile.familySize == 1 ? 'person' : 'people'}',
          ),
          const Divider(height: 20, color: _border),
          _detailRow(
            Icons.account_balance_wallet_outlined,
            'Monthly grocery budget',
            '₹${_formatBudget(profile.monthlyBudget)}',
          ),
          const Divider(height: 20, color: _border),
          _detailRow(
            Icons.restaurant_outlined,
            'Dietary preference',
            _prettyLabel(profile.dietaryPreference),
          ),
          if (goals.isNotEmpty) ...[
            const Divider(height: 20, color: _border),
            _detailRow(Icons.flag_outlined, 'Goals', goals.join(', ')),
          ],
          if (data.exclusions.isNotEmpty) ...[
            const Divider(height: 20, color: _border),
            _detailRow(
              Icons.remove_circle_outline,
              'Avoid',
              data.exclusions.join(', '),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Updates are used the next time you generate a meal plan.',
            style: TextStyle(fontSize: 10, color: _muted),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editFoodProfile(data),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit household & food preferences'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _orange,
                side: const BorderSide(color: Color(0xFFF0DFCC)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard(Map<String, dynamic> preferences) {
    return _card(
      child: Column(
        children: [
          const Text(
            'Saved for future notification support. Annora does not send these alerts yet.',
            style: TextStyle(fontSize: 11, height: 1.4, color: _muted),
          ),
          const SizedBox(height: 8),
          _notificationSwitch(
            preferences,
            'meal_plan_updates',
            'Meal plan updates',
            'When your plan changes',
          ),
          _notificationSwitch(
            preferences,
            'grocery_reminders',
            'Grocery reminders',
            'Shopping and pantry reminders',
          ),
          _notificationSwitch(
            preferences,
            'cooking_reminders',
            'Cooking reminders',
            'Reminders for planned meals',
          ),
        ],
      ),
    );
  }

  Widget _notificationSwitch(
    Map<String, dynamic> preferences,
    String key,
    String title,
    String subtitle,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeThumbColor: _green,
      title: Text(title, style: const TextStyle(fontSize: 12, color: _text)),
      subtitle:
          Text(subtitle, style: const TextStyle(fontSize: 10, color: _muted)),
      value: preferences[key] == true,
      onChanged: _savingNotifications
          ? null
          : (value) => _setNotificationPreference(key, value),
    );
  }

  Widget _buildAccountCard(String email) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(Icons.email_outlined, 'Signed in as', email),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _signingOut ? null : _signOut,
              icon: const Icon(Icons.logout, size: 17),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB34331),
                side: const BorderSide(color: Color(0xFFE8D3CE)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpSupportCard() {
    return _card(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        visualDensity: VisualDensity.compact,
        leading: const Icon(Icons.support_agent_outlined, color: _orange),
        title: const Text(
          'Contact Annora',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _text,
          ),
        ),
        subtitle: const Text(
          'Office address, email and phone',
          style: TextStyle(fontSize: 10, color: _muted),
        ),
        children: [
          const SizedBox(height: 10),
          _detailRow(
            Icons.location_on_outlined,
            'Office address',
            'Registered Office: Atal Center, BHU Varanasi, Uttar Pradesh –221005 India',
          ),
          const Divider(height: 20, color: _border),
          _detailRow(
            Icons.email_outlined,
            'Email',
            'annora.techie@gmail.com',
          ),
          const Divider(height: 20, color: _border),
          _detailRow(
            Icons.phone_outlined,
            'Phone number',
            '+91 9675866766',
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
          color: _muted,
        ),
      );

  Widget _buildBottomNav() {
    const items = [
      ('⌂', 'Home'),
      ('▦', 'Plan'),
      ('🛒', 'Shop'),
      ('📦', 'Pantry'),
      ('♙', 'Profile'),
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
          for (var index = 0; index < items.length; index++)
            GestureDetector(
              onTap: () {
                if (index == 0) widget.onOpenHome?.call();
                if (index == 1) widget.onOpenMealPlan?.call();
              },
              child: _ProfileNavItem(
                icon: items[index].$1,
                label: items[index].$2,
                selected: index == 4,
              ),
            ),
        ],
      ),
    );
  }

  String _prettyLabel(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  String _formatBudget(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
}

class _ProfileData {
  final OnboardingProfile? profile;
  final List<String> exclusions;
  final Map<String, dynamic> userProfile;

  const _ProfileData(this.profile, this.exclusions, this.userProfile);
}

class _ProfileEditSheet extends StatefulWidget {
  final OnboardingProfile profile;
  final List<String> exclusions;

  const _ProfileEditSheet({
    required this.profile,
    required this.exclusions,
  });

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  static const _preferences = [
    ('vegetarian', 'Vegetarian'),
    ('eggetarian', 'Eggetarian'),
    ('non_vegetarian', 'Non-vegetarian'),
    ('vegan', 'Vegan'),
    ('no_restriction', 'No restriction'),
  ];
  static const _goals = [
    ('keto', 'Keto'),
    ('diabetic_friendly', 'Diabetic-friendly'),
    ('high_protein', 'High protein'),
    ('low_sodium', 'Low sodium'),
    ('no_preference', 'No preference'),
  ];

  late int _familySize;
  late String _dietaryPreference;
  late Set<String> _dietaryGoals;
  late List<String> _exclusions;
  late final TextEditingController _budgetController;
  final _exclusionController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _familySize = widget.profile.familySize;
    _dietaryPreference = widget.profile.dietaryPreference;
    _dietaryGoals = widget.profile.dietaryGoals.toSet();
    _exclusions = [...widget.exclusions];
    _budgetController = TextEditingController(
      text: widget.profile.monthlyBudget.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _budgetController.dispose();
    _exclusionController.dispose();
    super.dispose();
  }

  void _addExclusion() {
    final value = _exclusionController.text.trim();
    if (value.isEmpty) return;
    if (_exclusions.any(
      (item) => item.toLowerCase() == value.toLowerCase(),
    )) {
      setState(() => _error = 'That ingredient is already on the list.');
      return;
    }
    setState(() {
      _exclusions.add(value);
      _exclusionController.clear();
      _error = null;
    });
  }

  void _save() {
    final budget = double.tryParse(_budgetController.text.trim());
    if (budget == null || budget <= 0) {
      setState(() => _error = 'Enter a monthly budget greater than zero.');
      return;
    }
    if (_dietaryPreference.isEmpty) {
      setState(() => _error = 'Choose a dietary preference.');
      return;
    }
    Navigator.pop(
      context,
      _ProfileEdits(
        familySize: _familySize,
        monthlyBudget: budget,
        dietaryPreference: _dietaryPreference,
        dietaryGoals: _dietaryGoals.toList(),
        exclusions: _exclusions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .9,
          minChildSize: .6,
          maxChildSize: .95,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Household & food preferences',
                        style: TextStyle(
                          color: Color(0xFF211C18),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    const Text('Household size'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _familySize > 1
                              ? () => setState(() => _familySize--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$_familySize ${_familySize == 1 ? 'person' : 'people'}',
                        ),
                        IconButton(
                          onPressed: _familySize < 20
                              ? () => setState(() => _familySize++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Monthly grocery budget'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _budgetController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Color(0xFF211C18)),
                      decoration: const InputDecoration(
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Dietary preference'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final option in _preferences)
                          ChoiceChip(
                            label: Text(option.$2),
                            selected: _dietaryPreference == option.$1,
                            onSelected: (_) => setState(
                              () => _dietaryPreference = option.$1,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text('Dietary goals'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final goal in _goals)
                          FilterChip(
                            label: Text(goal.$2),
                            selected: _dietaryGoals.contains(goal.$1),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _dietaryGoals.add(goal.$1);
                              } else {
                                _dietaryGoals.remove(goal.$1);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text('Avoid ingredients'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _exclusionController,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _addExclusion(),
                            style: const TextStyle(color: Color(0xFF211C18)),
                            decoration: const InputDecoration(
                              hintText: 'Add an ingredient',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _addExclusion,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    if (_exclusions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final exclusion in _exclusions)
                            InputChip(
                              label: Text(exclusion),
                              onDeleted: () => setState(
                                () => _exclusions.remove(exclusion),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Save preferences'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileEdits {
  final int familySize;
  final double monthlyBudget;
  final String dietaryPreference;
  final List<String> dietaryGoals;
  final List<String> exclusions;

  const _ProfileEdits({
    required this.familySize,
    required this.monthlyBudget,
    required this.dietaryPreference,
    required this.dietaryGoals,
    required this.exclusions,
  });
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, color: Color(0xFF7B746D)),
              const SizedBox(height: 10),
              Text(
                'Could not load profile: $message',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF7B746D)),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

class _ProfileNavItem extends StatelessWidget {
  final String icon;
  final String label;
  final bool selected;

  const _ProfileNavItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: 17,
                color: selected
                    ? const Color(0xFFF47A2A)
                    : const Color(0xFF82766A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: selected
                    ? const Color(0xFFF47A2A)
                    : const Color(0xFF82766A),
              ),
            ),
          ],
        ),
      );
}
