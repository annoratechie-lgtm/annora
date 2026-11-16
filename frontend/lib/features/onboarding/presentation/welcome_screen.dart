import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../state/auth_providers.dart';

/// Screen 1 of onboarding: pre-login trust builder (Figma: "V3 — Animated intro").
///
/// Blurred food-photo background with a dark scrim, the Annora logo that pops
/// in and then gently floats, the wordmark + tagline sliding up, testimonials,
/// and a single "Continue with Google" sign-in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> with TickerProviderStateMixin {
  final _pageController = PageController();
  int _page = 0;
  bool _signingIn = false;

  // Intro: 0.3s pause, logo pops in (0.7s), then wordmark + tagline (0.6s).
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  // Idle: logo floats up/down 6px forever once the intro is done.
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  late final Animation<double> _logoIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.19, 0.62, curve: Curves.easeOutBack),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.19, 0.45, curve: Curves.easeOut),
  );
  late final Animation<double> _wordIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.62, 1.0, curve: Curves.easeOut),
  );
  late final Animation<double> _taglineIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.68, 1.0, curve: Curves.easeOut),
  );
  late final Animation<double> _floatCurve = CurvedAnimation(parent: _float, curve: Curves.easeInOut);

  bool _started = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    precacheImage(const AssetImage(_Assets.background), context);
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1; // respect the OS "reduce motion" setting: no intro, no float
    } else {
      _intro.forward().whenComplete(() {
        if (mounted) _float.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _float.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background photo (blur is baked into the asset to keep web rendering cheap).
          Image.asset(_Assets.background, fit: BoxFit.cover),
          // Scrim: light at the top so the food shows, dark at the bottom for the CTA.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33120E0C), Color(0x4D120E0C), Color(0x8C120E0C), Color(0xE0120E0C)],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
          // Soft warm glow behind the logo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -1.05),
                radius: 0.75,
                colors: [Color(0x4D8A4A24), Color(0x008A4A24)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _buildContent(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        const SizedBox(height: 16),
        _buildLogo(),
        const SizedBox(height: 2),
        _slideFade(
          _wordIn,
          dy: 20,
          child: Image.asset(_Assets.wordmark, width: 184, semanticLabel: 'Annora'),
        ),
        const SizedBox(height: 10),
        _slideFade(
          _taglineIn,
          dy: 10,
          child: const Column(
            children: [
              Text(
                "Your household's AI food companion.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
              SizedBox(height: 6),
              Text(
                'Plan · Track · Nourish · Save.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textFaint, fontSize: 13, letterSpacing: 0.26),
              ),
            ],
          ),
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
        const SizedBox(height: 14),
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
        const SizedBox(height: 24),
        _GoogleButton(loading: _signingIn, onPressed: _signInWithGoogle),
        const SizedBox(height: 14),
        const Text.rich(
          TextSpan(
            style: TextStyle(color: AppColors.textFaint, fontSize: 11),
            children: [
              TextSpan(text: 'By continuing, you agree to our '),
              TextSpan(
                text: 'Terms',
                style: TextStyle(color: AppColors.textMuted, decoration: TextDecoration.underline),
              ),
              TextSpan(text: ' and '),
              TextSpan(
                text: 'Privacy Policy',
                style: TextStyle(color: AppColors.textMuted, decoration: TextDecoration.underline),
              ),
              TextSpan(text: '.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _float]),
      builder: (context, child) => Transform.translate(
        offset: Offset(0, 16 * (1 - _logoIn.value) - 6 * _floatCurve.value),
        child: Transform.scale(
          scale: 0.35 + 0.65 * _logoIn.value,
          child: Opacity(opacity: _logoFade.value.clamp(0.0, 1.0), child: child),
        ),
      ),
      child: Image.asset(_Assets.mark, width: 150, height: 125, semanticLabel: 'Annora logo'),
    );
  }

  Widget _slideFade(Animation<double> anim, {required double dy, required Widget child}) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, dy * (1 - anim.value)),
        child: Opacity(opacity: anim.value, child: child),
      ),
      child: child,
    );
  }
}

class _Assets {
  static const background = 'assets/images/login_bg.jpg';
  static const mark = 'assets/images/annora_mark.png';
  static const wordmark = 'assets/images/annora_wordmark.png';
  static const googleG = 'assets/images/google_g.png';
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

  String get initials => name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();
}

/// Frosted-glass testimonial card over the photo background.
class _TestimonialCard extends StatelessWidget {
  final _Testimonial data;
  const _TestimonialCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final onAvatar = data.avatarColor.computeLuminance() > 0.4 ? AppColors.background : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x8C221B17), // AppColors.card @ 55%
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '"${data.quote}"',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontStyle: FontStyle.italic,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: data.avatarColor,
                      child: Text(
                        data.initials,
                        style: TextStyle(color: onAvatar, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(data.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(data.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _GoogleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: Color(0x59FF7A3D), blurRadius: 24, spreadRadius: -6, offset: Offset(0, 8)),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.orange,
            disabledBackgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Image.asset(_Assets.googleG, width: 18, height: 18),
                    ),
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text(
                        'Continue with Google',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
