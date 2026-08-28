import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../shared/auth_page_scaffold.dart';
import 'change_password_page_model.dart';

export 'change_password_page_model.dart';

class ChangePasswordPageWidget extends ConsumerStatefulWidget {
  const ChangePasswordPageWidget({super.key});
  static const routeName = 'ChangePasswordPage';
  static const routePath = '/change-password';
  @override
  ConsumerState<ChangePasswordPageWidget> createState() =>
      _ChangePasswordPageWidgetState();
}

class _ChangePasswordPageWidgetState
    extends ConsumerState<ChangePasswordPageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0, .8, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0, .8, curve: Curves.easeOutCubic)));
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(changePasswordPageProvider);
    final notifier = ref.read(changePasswordPageProvider.notifier);
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        foregroundColor: theme.primaryText,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back to home',
        ),
      ),
      body: GestureDetector(
        onTap: FocusScope.of(context).unfocus,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: FadeTransition(
                        opacity: _fade,
                        child: SlideTransition(
                          position: _slide,
                          child: Form(
                            key: notifier.formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const AuthPageHeading(
                                  title: 'Update your\npassword',
                                  subtitle:
                                      'Choose a strong password you do not use anywhere else.',
                                ),
                                const SizedBox(height: 34),
                                AuthTextField(
                                  label: 'Current password',
                                  hint: 'Enter your current password',
                                  controller:
                                      notifier.currentPasswordController,
                                  focusNode: notifier.currentPasswordFocusNode,
                                  validator: notifier.validateCurrentPassword,
                                  prefixIcon: Icons.lock_outline_rounded,
                                  obscureText: !state.currentPasswordVisible,
                                  textInputAction: TextInputAction.next,
                                  onChanged: (_) => notifier.clearError(),
                                  onFieldSubmitted: (_) =>
                                      notifier.passwordFocusNode.requestFocus(),
                                  suffixIcon: _VisibilityButton(
                                    visible: state.currentPasswordVisible,
                                    onPressed: notifier
                                        .toggleCurrentPasswordVisibility,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                AuthTextField(
                                  label: 'New password',
                                  hint: 'At least 8 characters',
                                  controller: notifier.passwordController,
                                  focusNode: notifier.passwordFocusNode,
                                  validator: notifier.validatePassword,
                                  prefixIcon: Icons.lock_outline_rounded,
                                  obscureText: !state.newPasswordVisible,
                                  textInputAction: TextInputAction.next,
                                  onChanged: (_) => notifier.clearError(),
                                  onFieldSubmitted: (_) => notifier
                                      .confirmationFocusNode
                                      .requestFocus(),
                                  suffixIcon: _VisibilityButton(
                                    visible: state.newPasswordVisible,
                                    onPressed:
                                        notifier.toggleNewPasswordVisibility,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                AuthTextField(
                                  label: 'Confirm new password',
                                  hint: 'Re-enter your password',
                                  controller: notifier.confirmationController,
                                  focusNode: notifier.confirmationFocusNode,
                                  validator: notifier.validateConfirmation,
                                  prefixIcon: Icons.lock_outline_rounded,
                                  obscureText: !state.confirmPasswordVisible,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (_) => notifier.clearError(),
                                  onFieldSubmitted: (_) => _submit(notifier),
                                  suffixIcon: _VisibilityButton(
                                    visible: state.confirmPasswordVisible,
                                    onPressed: notifier
                                        .toggleConfirmPasswordVisibility,
                                  ),
                                ),
                                if (state.errorMessage != null) ...[
                                  const SizedBox(height: 18),
                                  AuthErrorBanner(state.errorMessage!),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: SizedBox(
                      width: double.infinity,
                      child: AuthPrimaryButton(
                        label: 'Update password',
                        isLoading: state.isSubmitting,
                        onPressed: () => _submit(notifier),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(ChangePasswordPageNotifier notifier) async {
    final success = await notifier.submit();
    if (!success || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')));
  }
}

class _VisibilityButton extends StatelessWidget {
  const _VisibilityButton({required this.visible, required this.onPressed});
  final bool visible;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      label: visible ? 'Hide password' : 'Show password',
      child: IconButton(
          onPressed: onPressed,
          tooltip: visible ? 'Hide password' : 'Show password',
          icon: Icon(visible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined)));
}
