import 'package:flutter/material.dart';

import '../data/assistant_api.dart';

class AssistantChat extends StatefulWidget {
  final AssistantApi api;

  const AssistantChat({super.key, required this.api});

  @override
  State<AssistantChat> createState() => _AssistantChatState();
}

class _AssistantChatState extends State<AssistantChat> {
  static const _text = Color(0xFF211C18);
  static const _muted = Color(0xFF7B746D);
  static const _orange = Color(0xFFF47A2A);
  static const _border = Color(0xFFE8E1D8);

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(message, isUser: true));
      _sending = true;
      _messageController.clear();
    });
    _scrollToLatest();

    try {
      final answer = await widget.api.ask(message);
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage(answer, isUser: false)));
    } on AssistantApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage("I couldn't answer that: ${error.message}",
              isUser: false),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToLatest();
      }
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚡ Annora Assist',
                style: TextStyle(
                  color: _text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Ask about your Annora profile, meals, nutrition, or grocery list. '
                'Your question and selected account data go to our AI provider; '
                'it cannot access other users’ accounts.',
                style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Hi! I can help with your Annora meal plan and saved preferences.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, height: 1.5),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return Align(
                      alignment: message.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: message.isUser
                              ? const Color(0xFFFFE9D7)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          message.text,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_sending) const LinearProgressIndicator(minHeight: 2),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: _border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: 'Ask Annora Assist...',
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFFAF7F1),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _sendMessage,
                style: IconButton.styleFrom(backgroundColor: _orange),
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                tooltip: 'Send message',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  const _ChatMessage(this.text, {required this.isUser});
}
