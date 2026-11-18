import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/annora_ui.dart';
import '../../assistant/data/assistant_api.dart';

/// Profile card: what Ask Annora remembers about the user. Facts are used in
/// chat and when planning meals; the user can add, edit and delete them.
class MemoryCard extends StatefulWidget {
  final AssistantApi api;
  const MemoryCard({super.key, required this.api});

  @override
  State<MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<MemoryCard> {
  List<MemoryFact>? _facts;
  String? _error;
  String? _editingId; // fact being edited, or 'new'
  final _field = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final facts = await widget.api.memory();
      if (mounted) {
        setState(() {
          _facts = facts;
          _error = null;
        });
      }
    } on AssistantApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _startEdit(String id, [String text = '']) => setState(() {
        _editingId = id;
        _field.text = text;
      });

  Future<void> _save() async {
    final text = _field.text.trim();
    final id = _editingId;
    if (id == null || text.length < 2) return;
    setState(() => _saving = true);
    try {
      if (id == 'new') {
        final fact = await widget.api.addMemory(text);
        _facts = [...?_facts, fact];
      } else {
        final fact = await widget.api.updateMemory(id, text);
        _facts = [for (final f in _facts ?? const <MemoryFact>[]) f.id == id ? fact : f];
      }
      _editingId = null;
    } on AssistantApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(MemoryFact fact) async {
    final before = _facts;
    setState(() => _facts = [...?_facts]..removeWhere((f) => f.id == fact.id));
    try {
      await widget.api.deleteMemory(fact.id);
    } on AssistantApiException catch (e) {
      if (mounted) setState(() => _facts = before);
      _snack(e.message);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final facts = _facts;
    return ACard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('What Annora remembers',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          if (facts != null && _editingId == null)
            LinkButton(label: 'Add', onTap: () => _startEdit('new')),
        ]),
        const SizedBox(height: 2),
        const Text('Used in Ask Annora and when planning your meals.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
        const SizedBox(height: 8),
        if (_error != null)
          Row(children: [
            Expanded(
                child: Text(_error!,
                    style: const TextStyle(color: AnnoraUi.danger, fontSize: 13))),
            LinkButton(label: 'Retry', onTap: _load),
          ])
        else if (facts == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.orange)),
          )
        else ...[
          if (facts.isEmpty && _editingId != 'new')
            const Text(
                'Nothing yet. Tell Annora things like "we don\'t eat bhindi" or "light dinners on weekdays".',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.4)),
          for (final f in facts)
            _editingId == f.id ? _editor() : _factRow(f),
          if (_editingId == 'new') _editor(),
        ],
      ]),
    );
  }

  Widget _factRow(MemoryFact f) => Container(
        key: ValueKey('memory-${f.id}'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AnnoraUi.line))),
        child: Row(children: [
          const Icon(Icons.bookmark_outline, size: 18, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(f.fact,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            onPressed: _editingId == null ? () => _startEdit(f.id, f.fact) : null,
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textMuted),
          ),
          IconButton(
            tooltip: 'Forget',
            visualDensity: VisualDensity.compact,
            onPressed: _editingId == null ? () => _delete(f) : null,
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
          ),
        ]),
      );

  Widget _editor() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const Key('memory-field'),
            controller: _field,
            autofocus: true,
            maxLength: 200,
            onSubmitted: (_) => _save(),
            cursorColor: AppColors.orange,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: "e.g. Doesn't like bhindi",
              hintStyle: const TextStyle(color: AppColors.textFaint),
              counterText: '',
              filled: true,
              fillColor: AnnoraUi.field,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AnnoraUi.line)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AnnoraUi.line)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            PrimaryButton(label: 'Save', busy: _saving, onTap: _save),
            if (!_saving)
              GhostButton(
                  label: 'Cancel', onTap: () => setState(() => _editingId = null)),
          ]),
        ]),
      );
}
