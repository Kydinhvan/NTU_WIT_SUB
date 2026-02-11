import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/responsive.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Responsive.centeredCard(
          context,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Text(
                  'How can Bridge\nhelp you today?',
                  style: AppTypography.heading1Serif,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.15, end: 0),

                const SizedBox(height: 48),

                _RoleCard(
                  icon: Icons.favorite_border_rounded,
                  title: 'I need support',
                  subtitle: 'Share what\'s on your mind.\nWe\'ll find someone who gets it.',
                  color: AppColors.amber,
                  onTap: () => context.go('/wellbeing-baseline/seeker'),
                ).animate(delay: 200.ms).fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),

                const SizedBox(height: 20),

                _RoleCard(
                  icon: Icons.volunteer_activism_rounded,
                  title: 'I want to help',
                  subtitle: 'Share your lived experience.\nBe the person you needed.',
                  color: AppColors.softSage,
                  onTap: () => context.go('/onboarding/helper-chat'),
                ).animate(delay: 350.ms).fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),

                const Spacer(),

                Text(
                  'Anonymous by default.\nNo accounts, no pressure.',
                  style: AppTypography.captionSans.copyWith(
                    color: AppColors.warmBrown.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ).animate(delay: 500.ms).fadeIn(duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.cream, size: 52),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.heading2Serif.copyWith(
                    color: AppColors.cream,
                  )),
                  const SizedBox(height: 6),
                  Text(subtitle, style: AppTypography.bodySerif.copyWith(
                    color: AppColors.cream.withValues(alpha: 0.85),
                    fontSize: 16,
                  )),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.cream.withValues(alpha: 0.7), size: 20),
          ],
        ),
      ),
    );
  }
}
