import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'features/assistant/data/assistant_api.dart';
import 'features/meal_plan/data/meal_plan_api.dart';
import 'features/meal_plan/data/meal_plan_config.dart';
import 'features/meal_plan/presentation/meal_plan_screen.dart';
import 'features/groceries/presentation/groceries_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/profile/data/user_profile_api.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/onboarding/data/onboarding_repository.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/onboarding/presentation/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: 'assets/env');
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ??
      const String.fromEnvironment('SUPABASE_URL');
  final supabaseKey = dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ??
      dotenv.env['SUPABASE_ANON_KEY'] ??
      const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
        defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
      );
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in frontend/.env.',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseKey,
  );

  runApp(const ProviderScope(child: AnnoraApp()));
}

class AnnoraApp extends StatelessWidget {
  const AnnoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mealPlanApi = MealPlanApi(baseUrl: mealPlanBackendUrl);
    final assistantApi = AssistantApi(baseUrl: mealPlanBackendUrl);
    final userProfileApi = UserProfileApi(baseUrl: mealPlanBackendUrl);

    return MaterialApp(
      title: 'Annora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = snapshot.hasData
              ? snapshot.data!.session
              : Supabase.instance.client.auth.currentSession;
          if (session == null) return const WelcomeScreen();

          return _OnboardingGate(
            key: ValueKey(session.user.id),
            mealPlanApi: mealPlanApi,
            assistantApi: assistantApi,
            userProfileApi: userProfileApi,
          );
        },
      ),
    );
  }
}

/// Shows onboarding until the signed-in user's profile is complete, then the
/// main app. Fetches the profile once per user (not on every rebuild) and
/// re-checks it when onboarding finishes.
class _OnboardingGate extends StatefulWidget {
  final MealPlanApi mealPlanApi;
  final AssistantApi assistantApi;
  final UserProfileApi userProfileApi;

  const _OnboardingGate({
    super.key,
    required this.mealPlanApi,
    required this.assistantApi,
    required this.userProfileApi,
  });

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  late Future<OnboardingProfile?> _profile =
      OnboardingRepository().fetchProfile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingProfile?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data?.onboardingCompleted == true) {
          return PostOnboardingShell(
            api: widget.mealPlanApi,
            assistantApi: widget.assistantApi,
            userProfileApi: widget.userProfileApi,
          );
        }
        return OnboardingScreen(
          saveProfile: ({required String name, String? phone}) async {
            await widget.userProfileApi.syncProfile(name: name, phone: phone);
          },
          onCompleted: () => setState(() {
            _profile = OnboardingRepository().fetchProfile();
          }),
        );
      },
    );
  }
}

class PostOnboardingShell extends StatefulWidget {
  final MealPlanApi api;
  final AssistantApi assistantApi;
  final UserProfileApi userProfileApi;

  const PostOnboardingShell({
    super.key,
    required this.api,
    required this.assistantApi,
    required this.userProfileApi,
  });

  @override
  State<PostOnboardingShell> createState() => _PostOnboardingShellState();
}

class _PostOnboardingShellState extends State<PostOnboardingShell> {
  static const _home = 0, _plan = 1, _groceries = 2, _profile = 3;
  int _selectedScreen = _home;

  void _go(int index) => setState(() => _selectedScreen = index);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(
          index: _selectedScreen,
          children: [
            HomeScreen(
              mealPlanApi: widget.api,
              assistantApi: widget.assistantApi,
              isActive: _selectedScreen == _home,
              onOpenMealPlan: () => _go(_plan),
              onOpenGroceries: () => _go(_groceries),
              onOpenProfile: () => _go(_profile),
            ),
            MealPlanScreen(
              api: widget.api,
              assistantApi: widget.assistantApi,
              isActive: _selectedScreen == _plan,
              onOpenHome: () => _go(_home),
              onOpenProfile: () => _go(_profile),
            ),
            GroceriesScreen(
              api: widget.api,
              isActive: _selectedScreen == _groceries,
              onOpenHome: () => _go(_home),
            ),
            ProfileScreen(
              api: widget.userProfileApi,
              assistantApi: widget.assistantApi,
              isActive: _selectedScreen == _profile,
              onOpenHome: () => _go(_home),
              onOpenMealPlan: () => _go(_plan),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: const Color(0xF0120E0C),
            indicatorColor: const Color(0x24FF7A3D),
            surfaceTintColor: Colors.transparent,
            labelTextStyle:
                WidgetStateProperty.resolveWith((states) => TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: states.contains(WidgetState.selected)
                          ? AppColors.orange
                          : AppColors.textFaint,
                    )),
            iconTheme:
                WidgetStateProperty.resolveWith((states) => IconThemeData(
                      color: states.contains(WidgetState.selected)
                          ? AppColors.orange
                          : AppColors.textFaint,
                    )),
          ),
          child: NavigationBar(
            height: 64,
            selectedIndex: _selectedScreen,
            onDestinationSelected: _go,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Plan'),
              NavigationDestination(
                  icon: Icon(Icons.shopping_bag_outlined),
                  selectedIcon: Icon(Icons.shopping_bag),
                  label: 'Groceries'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile'),
            ],
          ),
        ),
      );
}
