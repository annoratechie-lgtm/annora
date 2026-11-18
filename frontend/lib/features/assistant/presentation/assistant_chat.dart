import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/annora_ui.dart';
import '../data/assistant_api.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const quickPrompts = [
  "Swap tonight's dinner",
  'Make tomorrow lighter',
  'More protein this week',
  "How do I make today's lunch?",
];

/// The model is asked for plain text; strip any stray markdown it still sends.
String plainText(String text) => text
    .replaceAll('**', '')
    .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*[*•]\s+', multiLine: true), '- ')
    .trim();

String dayLabel(DateTime when, [DateTime? now]) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(when);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
}

/// Ask Annora: one continuous, saved chat. Plan changes arrive as proposals
/// that only happen when the user taps Apply.
class AssistantChat extends StatefulWidget {
  final AssistantApi api;

  /// Sent automatically when the chat opens (e.g. "How do I make Appam?").
  final String? initialMessage;

  /// Called after a proposal is applied, so screens can reload the plan.
  final VoidCallback? onPlanChanged;

  const AssistantChat(
      {super.key, required this.api, this.initialMessage, this.onPlanChanged});

  @override
  State<AssistantChat> createState() => _AssistantChatState();
}

class _AssistantChatState extends State<AssistantChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  final _rememberedAfter = <String, List<String>>{}; // reply id -> facts
  bool _loading = true;
  String? _loadError;
  bool _sending = false;
  String? _busyMessageId;
  bool _confirmClear = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final history = await widget.api.history();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
      });
    } on AssistantApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _scrollToEnd(jump: true);
    final initial = widget.initialMessage?.trim();
    if (_loadError == null && initial != null && initial.isNotEmpty) {
      _send(initial);
    }
  }

  Future<void> _send([String? text]) async {
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || _sending) return;
    final pending = ChatMessage(isUser: true, text: message);
    setState(() {
      _messages.add(pending);
      _sending = true;
      if (text == null) _input.clear();
    });
    _scrollToEnd();
    try {
      final turn = await widget.api.send(message);
      if (!mounted) return;
      setState(() {
        final i = _messages.indexOf(pending);
        if (i >= 0) _messages[i] = turn.userMessage;
        // A newer proposal replaces any older open one.
        if (turn.reply.action != null) _expireOpenProposals();
        _messages.add(turn.reply);
        if (turn.remembered.isNotEmpty && turn.reply.id != null) {
          _rememberedAfter[turn.reply.id!] = turn.remembered;
        }
      });
    } on AssistantApiException catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(
          isUser: false, text: "I couldn't answer that: ${e.message}", isError: true)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _expireOpenProposals() {
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].actionStatus == 'proposed') {
        _messages[i] = _messages[i].withStatus('expired');
      }
    }
  }

  Future<void> _apply(ChatMessage message) async {
    final id = message.id;
    if (id == null || _busyMessageId != null) return;
    setState(() => _busyMessageId = id);
    try {
      final result = await widget.api.apply(id);
      if (!mounted) return;
      setState(() {
        _expireOpenProposals();
        _replace(id, result.message);
        _messages.add(result.confirmation);
      });
      widget.onPlanChanged?.call();
      _scrollToEnd();
    } on AssistantApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 409) _replace(id, message.withStatus('expired'));
      });
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyMessageId = null);
    }
  }

  Future<void> _dismiss(ChatMessage message) async {
    final id = message.id;
    if (id == null || _busyMessageId != null) return;
    setState(() => _busyMessageId = id);
    try {
      final updated = await widget.api.dismiss(id);
      if (mounted) setState(() => _replace(id, updated));
    } on AssistantApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyMessageId = null);
    }
  }

  Future<void> _clear() async {
    try {
      await widget.api.clearChat();
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _rememberedAfter.clear();
        _confirmClear = false;
      });
    } on AssistantApiException catch (e) {
      _snack(e.message);
    }
  }

  void _replace(String id, ChatMessage updated) {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i >= 0) _messages[i] = updated;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      jump
          ? _scroll.jumpTo(end)
          : _scroll.animateTo(end,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(children: [
        _header(),
        if (_confirmClear)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ConfirmBox(
              message:
                  'Clear this chat? What Annora remembers (in Profile) stays.',
              confirmLabel: 'Clear chat',
              onConfirm: _clear,
              onCancel: () => setState(() => _confirmClear = false),
            ),
          ),
        Expanded(child: _body()),
        if (_sending) _thinking(),
        _composer(),
      ]),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 6, 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AnnoraUi.line))),
        child: Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.orange, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ask Annora',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Swaps, recipes and plan changes. Chats are kept 90 days.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ]),
          ),
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              onPressed: () => setState(() => _confirmClear = !_confirmClear),
              icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
            ),
        ]),
      );

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.orange));
    }
    if (_loadError != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load your chat",
        body: _loadError!,
        action: 'Try again',
        onAction: _loadHistory,
      );
    }
    if (_messages.isEmpty) return _welcome();

    final children = <Widget>[];
    String? lastDay;
    for (final m in _messages) {
      final day = dayLabel(m.createdAt);
      if (day != lastDay) {
        children.add(_divider(day));
        lastDay = day;
      }
      children.add(_bubble(m));
      if (m.action != null) children.add(_proposal(m));
      final facts = m.id == null ? null : _rememberedAfter[m.id];
      if (facts != null) children.add(_rememberedNote(facts));
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      children: children,
    );
  }

  Widget _welcome() => ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        children: [
          const Text('Hi! What would you like to change or cook?',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
              "I can swap meals, plan a fresh week, explain recipes and remember what you like. "
              "I'll always ask before changing your plan.",
              style: TextStyle(color: AppColors.textMuted, height: 1.45)),
          const SizedBox(height: 18),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in quickPrompts)
              ActionChip(
                label: Text(p),
                onPressed: _sending ? null : () => _send(p),
                backgroundColor: const Color(0x08FFFFFF),
                side: const BorderSide(color: AnnoraUi.lineStrong),
                shape: const StadiumBorder(),
                labelStyle: const TextStyle(color: AppColors.textPrimary),
              ),
          ]),
        ],
      );

  Widget _divider(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          const Expanded(child: Divider(color: AnnoraUi.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label,
                style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ),
          const Expanded(child: Divider(color: AnnoraUi.line)),
        ]),
      );

  Widget _bubble(ChatMessage m) => Align(
        alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: m.isUser
                ? AnnoraUi.accentSoft
                : m.isError
                    ? const Color(0x1AFF8A7A)
                    : AnnoraUi.card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(m.isUser ? 16 : 4),
              bottomRight: Radius.circular(m.isUser ? 4 : 16),
            ),
            border: Border.all(
                color: m.isUser ? const Color(0x40FF7A3D) : AnnoraUi.line),
          ),
          child: SelectableText(
            m.isUser ? m.text : plainText(m.text),
            style: TextStyle(
                color: m.isError ? AnnoraUi.danger : AppColors.textPrimary,
                fontSize: 14.5,
                height: 1.45),
          ),
        ),
      );

  Widget _proposal(ChatMessage m) {
    final action = m.action!;
    final status = m.actionStatus ?? 'proposed';
    final busy = _busyMessageId == m.id;
    return Container(
      key: ValueKey('proposal-${m.id}'),
      margin: const EdgeInsets.only(bottom: 10, right: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status == 'proposed' ? AnnoraUi.card2 : AnnoraUi.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: status == 'proposed'
                ? const Color(0x59FF7A3D)
                : AnnoraUi.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(action.type == 'new_week' ? Icons.calendar_month : Icons.swap_horiz,
              color: AppColors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                action.type == 'new_week' ? 'New week plan' : 'Suggested change',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        if (action.type == 'swap')
          for (final s in action.swaps) _swapLine(s)
        else
          Text(
              '${action.summary}. This replaces your current plan and grocery list.',
              style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
        const SizedBox(height: 10),
        if (status == 'proposed')
          Wrap(spacing: 8, runSpacing: 8, children: [
            PrimaryButton(
                label: action.type == 'new_week' ? 'Apply (takes ~30s)' : 'Apply',
                busy: busy,
                onTap: () => _apply(m)),
            if (!busy) GhostButton(label: 'Not now', onTap: () => _dismiss(m)),
          ])
        else
          _statusLine(status),
      ]),
    );
  }

  Widget _swapLine(ProposedSwap s) {
    final date = DateTime.tryParse(s.date);
    final when = date == null
        ? s.mealType
        : '${_weekdays[date.weekday - 1]} ${s.mealType}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$when: ',
              style: const TextStyle(color: AppColors.textMuted)),
          TextSpan(
              text: s.fromName,
              style: const TextStyle(
                  color: AppColors.textFaint,
                  decoration: TextDecoration.lineThrough)),
          const TextSpan(text: '  →  ', style: TextStyle(color: AppColors.orange)),
          TextSpan(
              text: s.toName,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ]),
        style: const TextStyle(fontSize: 14, height: 1.35),
      ),
    );
  }

  Widget _statusLine(String status) {
    final (icon, text, color) = switch (status) {
      'applied' => (Icons.check_circle, 'Applied to your plan', AnnoraUi.ok),
      'dismissed' => (Icons.do_not_disturb_on_outlined, 'Not applied', AppColors.textFaint),
      _ => (Icons.history, 'No longer valid. Ask again for a fresh suggestion.', AppColors.textFaint),
    };
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
    ]);
  }

  Widget _rememberedNote(List<String> facts) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Row(children: [
          const Icon(Icons.bookmark_added_outlined,
              size: 15, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Remembered: ${facts.join('; ')}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
        ]),
      );

  Widget _thinking() => const Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
        child: Row(children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.orange)),
          SizedBox(width: 10),
          Text('Annora is thinking…',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ]),
      );

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AnnoraUi.line))),
        child: SafeArea(
          top: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                key: const Key('assistant-input'),
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                cursorColor: AppColors.orange,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ask Annora…',
                  hintStyle: const TextStyle(color: AppColors.textFaint),
                  counterText: '',
                  filled: true,
                  fillColor: AnnoraUi.field,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AnnoraUi.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AnnoraUi.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0x59FF7A3D)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  disabledBackgroundColor: const Color(0x66FF7A3D)),
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              tooltip: 'Send message',
            ),
          ]),
        ),
      );
}

/// Opens Ask Annora as a bottom sheet, optionally asking [question] straight
/// away. Completes with true when a change was applied to the plan.
Future<bool> showAssistantSheet(BuildContext context, AssistantApi api,
    [String? question]) async {
  var changed = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    clipBehavior: Clip.antiAlias,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: AssistantChat(
          api: api,
          initialMessage: question,
          onPlanChanged: () => changed = true,
        ),
      ),
    ),
  );
  return changed;
}
