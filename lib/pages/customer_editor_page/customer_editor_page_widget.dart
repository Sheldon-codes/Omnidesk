import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'customer_editor_page_model.dart';

export 'customer_editor_page_model.dart';

class CustomerEditorPageWidget extends ConsumerStatefulWidget {
  const CustomerEditorPageWidget({super.key, this.customerId});

  final String? customerId;
  static const routeName = 'CustomerEditorPage';

  @override
  ConsumerState<CustomerEditorPageWidget> createState() =>
      _CustomerEditorPageWidgetState();
}

class _CustomerEditorPageWidgetState
    extends ConsumerState<CustomerEditorPageWidget> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _company;
  late final TextEditingController _notes;

  bool get _isEditing => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _email = TextEditingController();
    _phone = TextEditingController();
    _company = TextEditingController();
    _notes = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _company.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final provider =
        customerEditorNotifierProvider(customerId: widget.customerId);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    _sync(_name, state.name);
    _sync(_email, state.email);
    _sync(_phone, state.phone);
    _sync(_company, state.company);
    _sync(_notes, state.notes);

    if (_isEditing && state.initialCustomer == null) {
      return Scaffold(
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: context.pop,
                icon: Icon(IconsaxPlusBroken.arrow_left_2,
                    color: theme.primaryText),
              ),
            ),
            Expanded(
              child: Center(
                child: Text('Customer not found',
                    style:
                        theme.bodyLarge.override(color: theme.secondaryText)),
              ),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _CustomerEditorHeaderDelegate(
                theme: theme,
                title: _isEditing ? 'Edit customer' : 'Create customer',
                description: _isEditing
                    ? 'Update this customer’s contact details.'
                    : 'Add a customer to your workspace contacts.',
                onBack: context.pop,
              ),
            ),
            SliverToBoxAdapter(
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 124),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FieldLabel(
                          label: 'Name', theme: theme, requiredField: true),
                      const SizedBox(height: 8),
                      _EditorField(
                          controller: _name,
                          theme: theme,
                          hint: 'e.g. Nana Betterstream',
                          icon: IconsaxPlusBroken.user,
                          errorText: state.fieldErrors['name'],
                          onChanged: notifier.setName,
                          action: TextInputAction.next),
                      const SizedBox(height: 22),
                      _FieldLabel(label: 'Email', theme: theme),
                      const SizedBox(height: 8),
                      _EditorField(
                          controller: _email,
                          theme: theme,
                          hint: 'name@example.com',
                          icon: IconsaxPlusBroken.sms,
                          errorText: state.fieldErrors['email'],
                          onChanged: notifier.setEmail,
                          keyboardType: TextInputType.emailAddress,
                          action: TextInputAction.next),
                      const SizedBox(height: 22),
                      _FieldLabel(label: 'Phone number', theme: theme),
                      const SizedBox(height: 8),
                      _EditorField(
                          controller: _phone,
                          theme: theme,
                          hint: '+254 719 106 280',
                          icon: IconsaxPlusBroken.call,
                          errorText: state.fieldErrors['phone'],
                          onChanged: notifier.setPhone,
                          keyboardType: TextInputType.phone,
                          action: TextInputAction.next),
                      const SizedBox(height: 22),
                      _FieldLabel(label: 'Company', theme: theme),
                      const SizedBox(height: 8),
                      _EditorField(
                          controller: _company,
                          theme: theme,
                          hint: 'Company associated with this customer',
                          icon: IconsaxPlusBroken.building_4,
                          onChanged: notifier.setCompany,
                          action: TextInputAction.next),
                      const SizedBox(height: 22),
                      _FieldLabel(label: 'Notes', theme: theme),
                      const SizedBox(height: 8),
                      _EditorField(
                          controller: _notes,
                          theme: theme,
                          hint: 'Add notes about this customer',
                          icon: IconsaxPlusBroken.note,
                          onChanged: notifier.setNotes,
                          minLines: 4,
                          maxLines: 7),
                      if (state.failure != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Text(state.failure!,
                                style: theme.bodySmall
                                    .override(color: theme.error))),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: FilledButton(
            onPressed: state.submitting
                ? null
                : () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    final result = notifier.submit();
                    if (context.mounted && result != null) context.pop(result);
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: theme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: theme.primary.withValues(alpha: .45),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26)),
            ),
            child: state.submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_isEditing ? 'Save changes' : 'Create customer'),
          ),
        ),
      ),
    );
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text.isEmpty && value.isNotEmpty) controller.text = value;
  }
}

class _CustomerEditorHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CustomerEditorHeaderDelegate(
      {required this.theme,
      required this.title,
      required this.description,
      required this.onBack});
  final FlutterFlowTheme theme;
  final String title;
  final String description;
  final VoidCallback onBack;
  static const _expandedContent = 112.0;

  @override
  double get minExtent => kToolbarHeight;
  @override
  double get maxExtent => kToolbarHeight + _expandedContent;
  @override
  bool shouldRebuild(covariant _CustomerEditorHeaderDelegate old) =>
      old.title != title ||
      old.description != description ||
      old.theme != theme;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / _expandedContent).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        border: Border(
            bottom: BorderSide(
                color: theme.alternate
                    .withValues(alpha: progress > .85 ? .7 : 0))),
      ),
      child: Stack(children: [
        Positioned(
            left: 8,
            top: 0,
            child: SizedBox(
                width: 48,
                height: kToolbarHeight,
                child: IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: Icon(IconsaxPlusBroken.arrow_left_2,
                        color: theme.primaryText, size: 22)))),
        Positioned(
            left: lerpDouble(20, 58, progress)!,
            right: 20,
            top: lerpDouble(66, 16, progress)!,
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.headlineMedium.override(
                    color: theme.primaryText,
                    fontSize: lerpDouble(36, 20, progress)!,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1))),
        Positioned(
            left: 20,
            right: 20,
            top: 112,
            child: Opacity(
                opacity: (1 - progress * 1.35).clamp(0.0, 1.0),
                child: Text(description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium.override(
                        color: theme.secondaryText,
                        fontSize: 15,
                        lineHeight: 1.35)))),
      ]),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(
      {required this.label, required this.theme, this.requiredField = false});
  final String label;
  final FlutterFlowTheme theme;
  final bool requiredField;
  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label,
            style: theme.bodyMedium.override(
                color: theme.primaryText, fontWeight: FontWeight.w600)),
        if (requiredField)
          Text(' *',
              style: theme.bodyMedium
                  .override(color: theme.error, fontWeight: FontWeight.w700))
      ]);
}

class _EditorField extends StatelessWidget {
  const _EditorField(
      {required this.controller,
      required this.theme,
      required this.hint,
      required this.icon,
      this.onChanged,
      this.errorText,
      this.keyboardType,
      this.action,
      this.minLines = 1,
      this.maxLines = 1});
  final TextEditingController controller;
  final FlutterFlowTheme theme;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? action;
  final int minLines;
  final int maxLines;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DecoratedBox(
            decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: errorText == null ? theme.alternate : theme.error,
                    width: errorText == null ? 1 : 1.2)),
            child: TextField(
                controller: controller,
                onChanged: onChanged,
                keyboardType: keyboardType,
                textInputAction: action,
                minLines: minLines,
                maxLines: maxLines,
                style: theme.bodyLarge.override(color: theme.primaryText),
                decoration: InputDecoration(
                    hintText: hint,
                    hintStyle:
                        theme.bodyMedium.override(color: theme.secondaryText),
                    prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 14, right: 6),
                        child: Icon(icon, color: theme.primary, size: 20)),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16)))),
        if (errorText != null)
          Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(errorText!,
                  style: theme.bodySmall.override(color: theme.error)))
      ]);
}
