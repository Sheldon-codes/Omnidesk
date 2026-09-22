import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'whatsapp_live_store.dart';

/// In-app CRM composer for starting/reusing a WhatsApp DM through the
/// workspace's configured WhatsApp service. It never opens a personal app.
class WhatsAppComposeSheet extends ConsumerStatefulWidget {
  const WhatsAppComposeSheet({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.phone,
  });

  final String customerId;
  final String customerName;
  final String phone;

  static Future<int?> show(
    BuildContext context, {
    required String customerId,
    required String customerName,
    required String phone,
  }) =>
      showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        builder: (_) => WhatsAppComposeSheet(
          customerId: customerId,
          customerName: customerName,
          phone: phone,
        ),
      );

  @override
  ConsumerState<WhatsAppComposeSheet> createState() =>
      _WhatsAppComposeSheetState();
}

class _WhatsAppComposeSheetState extends ConsumerState<WhatsAppComposeSheet> {
  final _message = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) {
      if (text.isEmpty) setState(() => _error = 'Enter a message.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final ticketId = await ref.read(whatsAppRepositoryProvider).compose(
            customerId: widget.customerId,
            phone: widget.phone,
            name: widget.customerName,
            message: text,
          );
      if (mounted) Navigator.of(context).pop(ticketId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Message on WhatsApp',
              style: theme.titleLarge.override(
                  color: theme.primaryText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text('${widget.customerName} · ${widget.phone}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall.override(color: theme.secondaryText)),
          const SizedBox(height: 18),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 6,
            maxLength: 4096,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Write a message…',
              alignLabelWithHint: true,
              filled: true,
              fillColor: theme.secondaryBackground,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.alternate)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.alternate)),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: theme.bodySmall.override(color: theme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(IconsaxPlusBroken.send_2),
            label: Text(_sending ? 'Sending…' : 'Send message'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: theme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
