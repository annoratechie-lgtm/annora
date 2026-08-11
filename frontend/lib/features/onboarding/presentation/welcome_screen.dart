import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../state/auth_providers.dart';

/// Screen 1 of onboarding: pre-login trust builder. Shows the wordmark,
/// testimonials, and auth entry points. Buttons are UI-only for now --
/// wired to real Supabase auth in the next implementation step.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _testimonials = [
    _Testimonial(
      quote: 'Annora saved us ₹1,200 last month just on groceries. '
          'The price comparison is insane.',
      name: 'Meera Nair',
      detail: 'Bengaluru · Family of 4',
      avatarColor: AppColors.avatarGold,
    ),
    _Testimonial(
      quote: 'My maid just types in Hindi and it updates the pantry. '
          'Never run out of anything now.',
      name: 'Rahul Sharma',
      detail: 'Chennai · Family of 3',
      avatarColor: AppColors.avatarGreen,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.9),
            radius: 1.1,
            colors: [AppColors.glow, AppColors.background],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                const Text('✦', style: TextStyle(fontSize: 20, color: AppColors.textMuted)),
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: 'Ann',
                      style: AppTheme.displayFont.copyWith(
                        fontSize: 44,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: 'ora',
                      style: AppTheme.displayFont.copyWith(
                        fontSize: 44,
                        color: AppColors.orange,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Your household's AI food companion.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Plan · Track · Nourish · Save.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 13),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 172,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _testimonials.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => _TestimonialCard(data: _testimonials[i]),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_testimonials.length, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? AppColors.orange : AppColors.textFaint,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: wire to the auth screen in the next step.
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    ),
                    child: const Text(
                      'Get started free  →',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _AuthOptionButton(label: 'Phone', icon: Icons.phone_android, onTap: () {})),
                    const SizedBox(width: 12),
                    Expanded(child: _AuthOptionButton(label: 'Google', icon: Icons.g_mobiledata,onTap: () async {
                                                                                                              try {
                                                                                                                await ref.read(authRepositoryProvider).signInWithGoogle();
                                                                                                              } catch (e) {
                                                                                                                if (context.mounted) {
                                                                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                                                                    SnackBar(content: Text('Sign-in failed: $e')),
                                                                                                                  );
                                                                                                                }
                                                                                                              }
                                                                                                            },
),),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'No credit card · Free forever on basic plan',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Testimonial {
  final String quote;
  final String name;
  final String detail;
  final Color avatarColor;

  const _Testimonial({
    required this.quote,
    required this.name,
    required this.detail,
    required this.avatarColor,
  });
}

class _TestimonialCard extends StatelessWidget {
  final _Testimonial data;
  const _TestimonialCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '"${data.quote}"',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontStyle: FontStyle.italic,
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
          Row(
            children: [
              CircleAvatar(radius: 14, backgroundColor: data.avatarColor, child: const Text('🙂', style: TextStyle(fontSize: 12))),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(data.detail, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthOptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AuthOptionButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: AppColors.textPrimary),
      label: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.cardBorder),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}