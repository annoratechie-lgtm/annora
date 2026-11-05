import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'features/assistant/data/assistant_api.dart';
import 'features/meal_plan/data/meal_plan_api.dart';
import 'features/meal_plan/data/meal_plan_config.dart';
import 'features/meal_plan/presentation/meal_plan_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/profile/data/user_profile_api.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/onboarding/data/onboarding_repository.dart';
import 'features/onboarding/presentation/household_basics_screen.dart';
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
          final session = Supabase.instance.client.auth.currentSession;
          if (session == null) return const WelcomeScreen();

          return FutureBuilder<OnboardingProfile?>(
            future: OnboardingRepository().fetchProfile(),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final profile = profileSnapshot.data;
              return profile?.onboardingCompleted == true
                  ? PostOnboardingShell(
                      api: mealPlanApi,
                      assistantApi: assistantApi,
                      userProfileApi: userProfileApi,
                    )
                  : const HouseholdBasicsScreen();
            },
          );
        },
      ),
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
  int _selectedScreen = 0;

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: _selectedScreen,
        children: [
          HomeScreen(
            mealPlanApi: widget.api,
            isActive: _selectedScreen == 0,
            onOpenMealPlan: () => setState(() => _selectedScreen = 1),
            onOpenProfile: () => setState(() => _selectedScreen = 2),
          ),
          MealPlanScreen(
            api: widget.api,
            assistantApi: widget.assistantApi,
            isActive: _selectedScreen == 1,
            onOpenHome: () => setState(() => _selectedScreen = 0),
            onOpenProfile: () => setState(() => _selectedScreen = 2),
          ),
          ProfileScreen(
            api: widget.userProfileApi,
            isActive: _selectedScreen == 2,
            onOpenHome: () => setState(() => _selectedScreen = 0),
            onOpenMealPlan: () => setState(() => _selectedScreen = 1),
          ),
        ],
      );
}
