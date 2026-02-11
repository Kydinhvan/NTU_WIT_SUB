import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/conversation_modes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/responsive.dart';
import '../../../models/chat_message.dart';
import '../../../shared/services/firebase_service.dart';
import '../../../shared/services/scaffold_service.dart';

final _helperMessagesProvider = StateProvider<List<ChatMessage>>((ref) => [
  // Seed with seeker's opening message
  ChatMessage(
    id: 'seed_001',
    senderId: 'seeker_001',
    text: "I've been really struggling with my dad lately. We keep fighting about my future and I feel like nobody in my family understands me.",
    mode: 'vent',
    isAiScaffold: false,
    createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
  ),
]);

final _helperModeProvider = StateProvider<ConversationMode>((ref) => ConversationMode.vent);
final _scaffoldSuggestionProvider = StateProvider<String?>((ref) => null);

class ActiveChatScreen extends ConsumerStatefulWidget {
  const ActiveChatScreen({super.key});

  @override
  ConsumerState<ActiveChatScreen> createState() => _ActiveChatScreenState();
}

class _ActiveChatScreenState extends ConsumerState<ActiveChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _matchId = 'match_001';
  final _helperId = 'helper_001';

  // Cooldown: minimum 30s between scaffold API calls to stay within free-tier limits
  DateTime? _lastScaffoldCall;
  bool _scaffoldLoading = false;
  static const _scaffoldCooldown = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _refreshScaffold();
  }

  Future<void> _refreshScaffold({bool force = false}) async {
    if (_scaffoldLoading) return;
    final now = DateTime.now();
    if (!force &&
        _lastScaffoldCall != null &&
        now.difference(_lastScaffoldCall!) < _scaffoldCooldown) {
      // Still in cooldown — skip the API call silently
      return;
    }
    _scaffoldLoading = true;
    _lastScaffoldCall = now;
    try {
      final mode = ref.read(_helperModeProvider);
      final messages = ref.read(_helperMessagesProvider);
      final recent = messages
          .sublist(messages.length > 6 ? messages.length - 6 : 0)
          .map((m) => {'role': m.senderId == _helperId ? 'assistant' : 'user', 'content': m.text})
          .toList();
      final suggestion = await ScaffoldService.instance.getSuggestion(
        mode: mode,
        recentMessages: recent,
      );
      if (mounted) {
        ref.read(_scaffoldSuggestionProvider.notifier).state = suggestion;
      }
    } finally {
      _scaffoldLoading = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    final mode = ref.read(_helperModeProvider);
    final msg = ChatMessage(
      id: const Uuid().v4(),
      senderId: _helperId,
      text: text,
      mode: mode.name,
      isAiScaffold: false,
      createdAt: DateTime.now(),
    );

    ref.read(_helperMessagesProvider.notifier).update((msgs) => [...msgs, msg]);
    await FirebaseService.instance.sendMessage(_matchId, msg);
    _scrollToBottom();
    _refreshScaffold();
  }

  void _useSuggestion(String suggestion) {
    // Strip the Try: "..." prefix/suffix
    var clean = suggestion;
    if (clean.startsWith('Try: ')) clean = clean.substring(5);
    clean = clean.replaceAll('"', '').replaceAll("'", '');
    _controller.text = clean;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: clean.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(_helperMessagesProvider);
    final mode = ref.watch(_helperModeProvider);
    final suggestion = ref.watch(_scaffoldSuggestionProvider);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.warmBrown),
          onPressed: () => context.go('/helper/home'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active conversation', style: AppTypography.heading2Sans),
            Text('Anonymous seeker · ${mode.label}',
                style: AppTypography.captionSans),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _ModeBar(
            selected: mode,
            onSelect: (m) {
              ref.read(_helperModeProvider.notifier).state = m;
              _refreshScaffold(force: true);
            },
          ),
        ),
      ),
      body: Responsive.centeredCard(
        context,
        Column(
          children: [
            // AI scaffold suggestion rail
            if (suggestion != null)
              _ScaffoldRail(
                suggestion: suggestion,
                onUse: () => _useSuggestion(suggestion),
                onDismiss: () =>
                    ref.read(_scaffoldSuggestionProvider.notifier).state = null,
              ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),

            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: messages.length,
                itemBuilder: (_, i) => _MessageBubble(
                  message: messages[i],
                  isHelper: messages[i].senderId == _helperId,
                ),
              ),
            ),

            _InputBar(controller: _controller, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  final ConversationMode selected;
  final void Function(ConversationMode) onSelect;
  const _ModeBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: ConversationMode.values.map((mode) {
          final isSelected = mode == selected;
          return GestureDetector(
            onTap: () => onSelect(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.softSage
                    : AppColors.softSage.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(mode.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(mode.label, style: AppTypography.labelSans.copyWith(
                    color: isSelected ? AppColors.cream : AppColors.softSage,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ScaffoldRail extends StatelessWidget {
  final String suggestion;
  final VoidCallback onUse;
  final VoidCallback onDismiss;
  const _ScaffoldRail({
    required this.suggestion,
    required this.onUse,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softSage.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.softSage.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, size: 14, color: AppColors.softSage),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              suggestion,
              style: AppTypography.captionSans.copyWith(
                color: AppColors.warmBrown,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onUse,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.softSage,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Use', style: AppTypography.captionSans.copyWith(
                color: AppColors.cream, fontWeight: FontWeight.w700,
              )),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded,
                size: 16, color: AppColors.warmBrown.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isHelper;
  const _MessageBubble({required this.message, required this.isHelper});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: isHelper ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.75,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: isHelper ? AppColors.softSage : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isHelper ? 20 : 4),
                    bottomRight: Radius.circular(isHelper ? 4 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.warmBrown.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message.text,
                  style: AppTypography.bodySerif.copyWith(
                    fontSize: 17,
                    color: isHelper ? AppColors.cream : AppColors.charcoal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      decoration: BoxDecoration(
        color: AppColors.cream,
        boxShadow: [
          BoxShadow(
            color: AppColors.warmBrown.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              style: AppTypography.bodySans.copyWith(fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Respond thoughtfully...',
                hintStyle: AppTypography.bodySans.copyWith(
                  color: AppColors.warmBrown.withValues(alpha: 0.35),
                ),
                filled: true,
                fillColor: AppColors.warmBrown.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.softSage,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: AppColors.cream),
            ),
          ),
        ],
      ),
    );
  }
}
