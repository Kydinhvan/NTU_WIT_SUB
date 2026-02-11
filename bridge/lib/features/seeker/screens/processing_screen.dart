import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/services/matching_service.dart';
import '../../../models/seeker_profile.dart';
import '../../../models/match_result.dart';

class ProcessingScreen extends StatefulWidget {
  final String? transcript;
  const ProcessingScreen({super.key, this.transcript});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  int _step = 0;

  static const _stepIcons = [
    Icons.hearing_rounded,
    Icons.psychology_rounded,
    Icons.group_rounded,
  ];

  final _steps = [
    {'label': 'Listening to you...'},
    {'label': 'Understanding your situation...'},
    {'label': 'Finding someone who truly gets it...'},
  ];

  @override
  void initState() {
    super.initState();
    _runPipeline();
  }

  Future<void> _runPipeline() async {
    final transcript = widget.transcript ?? '';
    debugPrint('[BRIDGE][PIPELINE] Starting pipeline. Transcript: "$transcript"');

    // Step 1: transcription visual
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _step = 1);
    debugPrint('[BRIDGE][PIPELINE] Step 1 done — transcript received');

    // Step 2: profile extraction (mock)
    await Future.delayed(const Duration(seconds: 1, milliseconds: 500));
    if (mounted) setState(() => _step = 2);
    debugPrint('[BRIDGE][PIPELINE] Step 2 done — profile extracted');

    // Step 3: matching
    debugPrint('[BRIDGE][MATCH] Calling findMatch with transcript...');
    try {
      final result = await MatchingService.instance.findMatch(
        SeekerProfile.mock(),
        null, // Use full helper pool — don't filter by IDs
      );
      debugPrint('[BRIDGE][MATCH] Match result: helperId=${result.helperId}, score=${result.score}');
      debugPrint('[BRIDGE][MATCH] Breakdown: ${result.breakdown}');
      debugPrint('[BRIDGE][MATCH] Explanation: ${result.explanation}');
      if (!mounted) return;
      context.go('/seeker/match-reveal', extra: result);
    } catch (e) {
      debugPrint('[BRIDGE][MATCH] Matching failed: $e — falling back to mock result');
      if (!mounted) return;
      final mock = MatchResult.mock();
      debugPrint('[BRIDGE][MATCH] Mock result: helperId=${mock.helperId}, score=${mock.score}');
      context.go('/seeker/match-reveal', extra: mock);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Responsive.centeredCard(
        context,
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing ring
            _PulsingRing(),
            const SizedBox(height: 48),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Column(
                key: ValueKey(_step),
                children: [
                  Icon(
                    _stepIcons[_step],
                    size: 52,
                    color: AppColors.amber,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _steps[_step]['label']!,
                    style: AppTypography.heading2Serif,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: LinearProgressIndicator(
                value: (_step + 1) / _steps.length,
                backgroundColor: AppColors.amber.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(AppColors.amber),
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingRing extends StatefulWidget {
  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final scale = 1.0 + _controller.value * 0.12;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.amber.withValues(alpha: 0.1 + _controller.value * 0.1),
              border: Border.all(
                color: AppColors.amber.withValues(alpha: 0.3 + _controller.value * 0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(Icons.hub_rounded, size: 40,
                  color: AppColors.amber.withValues(alpha: 0.6 + _controller.value * 0.4)),
            ),
          ),
        );
      },
    );
  }
}
