import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dark UI tokens and small building blocks shared by the main tabs.
class AnnoraUi {
  static const card = Color(0xFF1E1815);
  static const card2 = Color(0xFF261F1A);
  static const field = Color(0xFF1A1411);
  static const line = Color(0x14FFFFFF);
  static const lineStrong = Color(0x26FFFFFF);
  static const accentSoft = Color(0x24FF7A3D);
  static const warn = Color(0xFFF2B544);
  static const ok = Color(0xFF7BC47F);
  static const danger = Color(0xFFFF8A7A);
}

/// Page scaffold: dark ground, warm glow, phone-width column.
class AnnoraPage extends StatelessWidget {
  final Widget child;
  const AnnoraPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.25),
                  radius: 0.9,
                  colors: [Color(0x598A4A24), Color(0x008A4A24)],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: child),
            ),
          ),
        ]),
      );
}

class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const PageTitle(
      {super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: AppTheme.displayFont.copyWith(
                    fontSize: 28, height: 1.1, color: AppColors.textPrimary)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13.5)),
            ],
          ]),
        ),
        if (trailing != null) trailing!,
      ]);
}

class ACard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const ACard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  // A Material surface (not a coloured box) so ripples from list tiles,
  // switches and ink wells inside the card stay visible.
  @override
  Widget build(BuildContext context) => Material(
        color: AnnoraUi.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AnnoraUi.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}

class SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600)),
          ),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 12.5)),
        ]),
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool expand;
  const PrimaryButton(
      {super.key,
      required this.label,
      this.onTap,
      this.busy = false,
      this.expand = false});

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0x99FF7A3D),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const StadiumBorder(),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white))
            : Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  const GhostButton({super.key, required this.label, this.onTap, this.color});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color ?? AppColors.textPrimary,
          side: BorderSide(
              color: color?.withValues(alpha: .45) ?? AnnoraUi.lineStrong),
          minimumSize: const Size(0, 44),
          shape: const StadiumBorder(),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

class LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const LinkButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      );
}

/// Inline "are you sure?" box used instead of dialogs for destructive actions.
class ConfirmBox extends StatelessWidget {
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool busy;

  const ConfirmBox({
    super.key,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.cancelLabel = 'Cancel',
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AnnoraUi.accentSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x59FF7A3D)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            PrimaryButton(label: confirmLabel, onTap: onConfirm, busy: busy),
            if (!busy) GhostButton(label: cancelLabel, onTap: onCancel),
          ]),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: AnnoraUi.accentSoft,
                borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, color: AppColors.orange, size: 30),
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
          if (action != null)
            PrimaryButton(label: action!, onTap: onAction, busy: busy),
        ]),
      );
}
