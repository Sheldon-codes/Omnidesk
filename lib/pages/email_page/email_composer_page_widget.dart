import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import 'email_attachment_picker.dart';
import 'email_draft_repository.dart';
import 'email_page_model.dart';

final emailDraftRepositoryProvider = Provider<EmailDraftRepository>(
  (_) => SqliteEmailDraftRepository(),
);

class EmailComposerPageWidget extends ConsumerStatefulWidget {
  const EmailComposerPageWidget({
    super.key,
    this.threadId,
    this.mode = EmailComposerMode.newMessage,
    this.initialTo,
  });

  static const routeName = 'EmailComposerPage';
  final String? threadId;
  final EmailComposerMode mode;
  final String? initialTo;

  @override
  ConsumerState<EmailComposerPageWidget> createState() =>
      _EmailComposerPageWidgetState();
}

class _EmailComposerPageWidgetState
    extends ConsumerState<EmailComposerPageWidget> with WidgetsBindingObserver {
  late final QuillController _editor;
  late final EmailDraftRepository _draftRepository;
  late final TextEditingController _recipientInput;
  late final TextEditingController _subject;
  Timer? _saveDebounce;
  var _to = <EmailAddress>[];
  var _cc = <EmailAddress>[];
  var _bcc = <EmailAddress>[];
  var _attachments = <EmailAttachment>[];
  var _showCcBcc = false;
  var _showQuotedHistory = false;
  var _loadingDraft = true;
  var _sending = false;

  String get _draftKey =>
      emailDraftKey(threadId: widget.threadId, mode: widget.mode);
  EmailThread? get _thread => widget.threadId == null
      ? null
      : ref.read(emailStoreProvider.notifier).findById(widget.threadId!);

  @override
  void initState() {
    super.initState();
    _draftRepository = ref.read(emailDraftRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _editor = QuillController.basic();
    _recipientInput = TextEditingController();
    _subject = TextEditingController();
    _editor.addListener(_scheduleSave);
    _subject.addListener(_scheduleSave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreDraft();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveDraft());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    unawaited(_saveDraft());
    _editor
      ..removeListener(_scheduleSave)
      ..dispose();
    _recipientInput.dispose();
    _subject
      ..removeListener(_scheduleSave)
      ..dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final saved = await _draftRepository.load(_draftKey);
    if (!mounted) return;
    if (saved != null) {
      _applyDraft(saved);
    } else {
      _applyInitialValues();
    }
    setState(() => _loadingDraft = false);
  }

  void _applyInitialValues() {
    final thread = _thread;
    if (widget.initialTo != null && widget.initialTo!.isNotEmpty) {
      _to = [EmailAddress(address: widget.initialTo!)];
    } else if (thread != null && widget.mode != EmailComposerMode.forward) {
      _to = _replyRecipients(thread, widget.mode);
    }
    if (thread != null) {
      _subject.text = _subjectFor(thread.subject, widget.mode);
      _showQuotedHistory = widget.mode == EmailComposerMode.forward;
    }
  }

  void _applyDraft(EmailDraft draft) {
    _to = draft.to;
    _cc = draft.cc;
    _bcc = draft.bcc;
    _attachments = draft.attachments;
    _subject.text = draft.subject;
    _showQuotedHistory = draft.showQuotedHistory;
    if (draft.deltaJson.isNotEmpty) {
      _editor.document = Document.fromJson(draft.deltaJson);
    }
  }

  List<EmailAddress> _replyRecipients(
      EmailThread thread, EmailComposerMode mode) {
    final source = thread.latestMessage;
    final values = <EmailAddress>[
      source.replyTo ?? source.from,
      if (mode == EmailComposerMode.replyAll) ...source.to,
      if (mode == EmailComposerMode.replyAll) ...source.cc,
    ];
    return _dedupeAddresses(values);
  }

  String _subjectFor(String source, EmailComposerMode mode) {
    if (mode == EmailComposerMode.newMessage) return '';
    final prefix = mode == EmailComposerMode.forward ? 'Fwd: ' : 'Re: ';
    return source.toLowerCase().startsWith(prefix.toLowerCase())
        ? source
        : '$prefix$source';
  }

  void _scheduleSave() {
    if (_loadingDraft) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _saveDraft() async {
    if (_loadingDraft) return;
    await _draftRepository.save(
      EmailDraft(
        key: _draftKey,
        threadId: widget.threadId,
        mode: widget.mode,
        deltaJson: _deltaJson(),
        updatedAt: DateTime.now(),
        to: _to,
        cc: _cc,
        bcc: _bcc,
        subject: _subject.text,
        attachments: _attachments,
        showQuotedHistory: _showQuotedHistory,
      ),
    );
  }

  List<Map<String, dynamic>> _deltaJson() => _editor.document
      .toDelta()
      .toJson()
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);

  List<EmailAddress> _dedupeAddresses(Iterable<EmailAddress> values) {
    final seen = <String>{agentMailbox};
    return [
      for (final value in values)
        if (value.isValid && seen.add(value.normalized)) value,
    ];
  }

  void _addRecipient(String raw, {required _RecipientField field}) {
    final parsed = raw
        .split(RegExp(r'[,;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => EmailAddress(address: value));
    final valid = _dedupeAddresses(parsed);
    if (valid.isEmpty && raw.trim().isNotEmpty) {
      _snack('Enter a valid email address');
      return;
    }
    setState(() {
      if (field == _RecipientField.to) {
        _to = _dedupeAddresses([..._to, ...valid]);
      } else if (field == _RecipientField.cc) {
        _cc = _dedupeAddresses([..._cc, ...valid, ..._to]);
        _cc.removeWhere(
          (item) => _to.any((to) => to.normalized == item.normalized),
        );
      } else {
        _bcc = _dedupeAddresses([..._bcc, ...valid, ..._to, ..._cc]);
        _bcc.removeWhere(
          (item) =>
              _to.any((to) => to.normalized == item.normalized) ||
              _cc.any((cc) => cc.normalized == item.normalized),
        );
      }
      _recipientInput.clear();
    });
    _scheduleSave();
  }

  Future<void> _pickAttachment(_AttachmentSource source) async {
    try {
      final picker = ref.read(emailAttachmentPickerProvider);
      final selected = switch (source) {
        _AttachmentSource.document => await picker.pickDocuments(_draftKey),
        _AttachmentSource.photo =>
          await picker.pickMedia(_draftKey, camera: false),
        _AttachmentSource.camera =>
          await picker.pickMedia(_draftKey, camera: true),
      };
      if (!mounted || selected.isEmpty) return;
      setState(() => _attachments = [..._attachments, ...selected]);
      final blocked = selected.where((item) => item.isBlocked).length;
      if (blocked > 0) {
        _snack('$blocked attachment${blocked == 1 ? '' : 's'} cannot be sent');
      }
      _scheduleSave();
    } catch (_) {
      if (mounted) _snack('Unable to attach that file. Please try again.');
    }
  }

  Future<void> _showAttachmentSheet() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAttachment(_AttachmentSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo or video'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAttachment(_AttachmentSource.photo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAttachment(_AttachmentSource.document);
              },
            ),
            const SizedBox(height: 12),
          ]),
        ),
      );

  Future<void> _send() async {
    final recipients = _dedupeAddresses(_to);
    final plain = _editor.document.toPlainText().trim();
    final attachmentsReady = _attachments.every(
      (item) =>
          !item.isBlocked &&
          item.uploadState == EmailAttachmentUploadState.localReady,
    );
    if (recipients.isEmpty) {
      return _snack('Add at least one valid recipient');
    }
    if (_subject.text.trim().isEmpty && plain.isEmpty && _attachments.isEmpty) {
      return _snack('Add a subject, message, or attachment');
    }
    if (plain.isEmpty) {
      return _snack('Add a message before sending');
    }
    if (!attachmentsReady) {
      return _snack('Remove or retry unavailable attachments');
    }
    final thread = _thread;
    if (thread == null && _attachments.isNotEmpty) {
      return _snack('Attachments are not supported for new emails yet');
    }
    setState(() => _sending = true);
    try {
      if (thread == null) {
        await ref.read(emailStoreProvider.notifier).createRemote(
              to: recipients.first.address,
              customerName: recipients.first.name,
              subject: _subject.text.trim().isEmpty
                  ? '(No subject)'
                  : _subject.text.trim(),
              message: plain,
            );
      } else {
        await ref.read(emailStoreProvider.notifier).reply(
              thread.id,
              plain,
              attachment: _attachments.isEmpty ? null : _attachments.first,
            );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        _snack(error.toString().replaceFirst('Exception: ', ''));
      }
      return;
    }
    await _draftRepository.delete(_draftKey);
    if (!mounted) return;
    _snack('Email sent');
    context.pop();
  }

  void _toggleFormat(Attribute attribute) => _editor.formatSelection(attribute);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loadingDraft) {
      return Scaffold(
        backgroundColor: theme.primaryBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          _ComposerHeader(
            title: _modeLabel(widget.mode),
            sending: _sending,
            onCancel: context.pop,
            onSend: _sending ? null : _send,
            theme: theme,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              children: [
                _fromRow(theme),
                _recipientRow(_RecipientField.to, 'To', _to,
                    requiredField: true, theme: theme),
                if (_showCcBcc) ...[
                  _recipientRow(_RecipientField.cc, 'Cc', _cc, theme: theme),
                  _recipientRow(_RecipientField.bcc, 'Bcc', _bcc, theme: theme),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _showCcBcc = true),
                      child: const Text('Cc/Bcc'),
                    ),
                  ),
                _subjectField(theme),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 230),
                  child: QuillEditor.basic(
                    controller: _editor,
                    config: const QuillEditorConfig(
                      placeholder: 'Write your message…',
                      padding: EdgeInsets.zero,
                      autoFocus: false,
                      scrollable: false,
                    ),
                  ),
                ),
                if (_attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final attachment in _attachments)
                    _AttachmentRow(
                      attachment: attachment,
                      onRemove: () {
                        setState(() => _attachments = _attachments
                            .where((item) => item.id != attachment.id)
                            .toList(growable: false));
                        _scheduleSave();
                      },
                      theme: theme,
                    ),
                ],
                if (_thread != null) _quotedHistory(theme),
              ],
            ),
          ),
          _ComposerToolbar(
            onAttachment: _showAttachmentSheet,
            onBold: () => _toggleFormat(Attribute.bold),
            onItalic: () => _toggleFormat(Attribute.italic),
            onUnderline: () => _toggleFormat(Attribute.underline),
            onList: () => _toggleFormat(Attribute.ul),
            onUndo: _editor.undo,
            onRedo: _editor.redo,
            theme: theme,
          ),
        ]),
      ),
    );
  }

  Widget _fromRow(FlutterFlowTheme theme) => _MetadataRow(
        label: 'From',
        child: Text('OmniDesk Support <$agentMailbox>',
            style: theme.bodyMedium.override(
                fontFamily: theme.bodyMediumFamily, color: theme.primaryText)),
      );

  Widget _recipientRow(
      _RecipientField field, String label, List<EmailAddress> values,
      {bool requiredField = false, required FlutterFlowTheme theme}) {
    final suggestions = ref
        .watch(customersStoreProvider)
        .where((item) => item.email.isNotEmpty)
        .map((item) => EmailAddress(address: item.email, name: item.name))
        .where((item) =>
            !values.any((selected) => selected.normalized == item.normalized))
        .toList(growable: false);
    return _MetadataRow(
      label: requiredField ? '$label *' : label,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (values.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final address in values)
              InputChip(
                label: Text(address.label, overflow: TextOverflow.ellipsis),
                onDeleted: () {
                  setState(() {
                    if (field == _RecipientField.to) {
                      _to = _to
                          .where(
                              (item) => item.normalized != address.normalized)
                          .toList(growable: false);
                    } else if (field == _RecipientField.cc) {
                      _cc = _cc
                          .where(
                              (item) => item.normalized != address.normalized)
                          .toList(growable: false);
                    } else {
                      _bcc = _bcc
                          .where(
                              (item) => item.normalized != address.normalized)
                          .toList(growable: false);
                    }
                  });
                  _scheduleSave();
                },
              ),
          ]),
        Autocomplete<EmailAddress>(
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            if (query.isEmpty) return const Iterable<EmailAddress>.empty();
            return suggestions.where((item) =>
                item.label.toLowerCase().contains(query) ||
                item.address.toLowerCase().contains(query));
          },
          displayStringForOption: (option) => option.address,
          onSelected: (option) => _addRecipient(option.address, field: field),
          fieldViewBuilder: (_, controller, focusNode, __) {
            if (field == _RecipientField.to) {
              _recipientInput.value = controller.value;
            }
            return TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Add recipient',
                hintStyle: TextStyle(color: theme.secondaryText),
              ),
              onSubmitted: (value) => _addRecipient(value, field: field),
              onChanged: (value) {
                if (value.endsWith(',') || value.endsWith(';')) {
                  _addRecipient(value, field: field);
                }
              },
            );
          },
        ),
      ]),
    );
  }

  Widget _subjectField(FlutterFlowTheme theme) => _MetadataRow(
        label: 'Subject',
        child: TextField(
          controller: _subject,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Subject',
            hintStyle: TextStyle(color: theme.secondaryText),
          ),
        ),
      );

  Widget _quotedHistory(FlutterFlowTheme theme) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextButton.icon(
            onPressed: () {
              setState(() => _showQuotedHistory = !_showQuotedHistory);
              _scheduleSave();
            },
            icon: Icon(
                _showQuotedHistory ? Icons.expand_less : Icons.expand_more),
            label: Text(
                _showQuotedHistory ? 'Hide quoted email' : 'Show quoted email'),
          ),
          if (_showQuotedHistory)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.secondaryBackground,
              child: SelectableText(
                _thread!.latestMessage.body.plainText,
                maxLines: 8,
                style: theme.bodySmall.override(
                    fontFamily: theme.bodySmallFamily,
                    color: theme.secondaryText),
              ),
            ),
        ]),
      );

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

enum _RecipientField { to, cc, bcc }

enum _AttachmentSource { camera, photo, document }

String _modeLabel(EmailComposerMode mode) => switch (mode) {
      EmailComposerMode.newMessage => 'New email',
      EmailComposerMode.reply => 'Reply',
      EmailComposerMode.replyAll => 'Reply all',
      EmailComposerMode.forward => 'Forward',
    };

class _ComposerHeader extends StatelessWidget {
  const _ComposerHeader(
      {required this.title,
      required this.sending,
      required this.onCancel,
      required this.onSend,
      required this.theme});
  final String title;
  final bool sending;
  final VoidCallback onCancel;
  final VoidCallback? onSend;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Row(children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          Expanded(
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: theme.titleSmall.override(
                      fontFamily: theme.titleSmallFamily,
                      color: theme.primaryText,
                      fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: onSend,
              child: sending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send')),
        ]),
      );
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            border: Border(
                bottom:
                    BorderSide(color: FlutterFlowTheme.of(context).alternate))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 62,
              child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      style: FlutterFlowTheme.of(context).bodySmall))),
          Expanded(child: child),
        ]),
      );
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow(
      {required this.attachment, required this.onRemove, required this.theme});
  final EmailAttachment attachment;
  final VoidCallback onRemove;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
            attachment.isImage
                ? Icons.image_outlined
                : Icons.insert_drive_file_outlined,
            color: theme.secondaryText),
        title: Text(attachment.filename,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${(attachment.byteCount / 1024).ceil()} KB · ${attachment.isBlocked ? attachment.failureMessage ?? 'Blocked' : 'Ready'}'),
        trailing: IconButton(
            tooltip: 'Remove attachment',
            onPressed: onRemove,
            icon: const Icon(Icons.close)),
      );
}

class _ComposerToolbar extends StatelessWidget {
  const _ComposerToolbar(
      {required this.onAttachment,
      required this.onBold,
      required this.onItalic,
      required this.onUnderline,
      required this.onList,
      required this.onUndo,
      required this.onRedo,
      required this.theme});
  final VoidCallback onAttachment;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onList;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.alternate))),
          child: Row(children: [
            IconButton(
                tooltip: 'Attach file',
                onPressed: onAttachment,
                icon: const Icon(Icons.attach_file)),
            _formatButton('B', onBold, FontWeight.w700),
            _formatButton('I', onItalic, FontWeight.normal, italic: true),
            _formatButton('U', onUnderline, FontWeight.normal, underline: true),
            IconButton(
                tooltip: 'Bulleted list',
                onPressed: onList,
                icon: const Icon(Icons.format_list_bulleted)),
            const Spacer(),
            IconButton(
                tooltip: 'Undo',
                onPressed: onUndo,
                icon: const Icon(Icons.undo)),
            IconButton(
                tooltip: 'Redo',
                onPressed: onRedo,
                icon: const Icon(Icons.redo)),
          ]),
        ),
      );
  Widget _formatButton(String text, VoidCallback onPressed, FontWeight weight,
          {bool italic = false, bool underline = false}) =>
      IconButton(
        tooltip: 'Format $text',
        onPressed: onPressed,
        icon: Text(text,
            style: TextStyle(
                fontWeight: weight,
                fontStyle: italic ? FontStyle.italic : null,
                decoration: underline ? TextDecoration.underline : null)),
      );
}
