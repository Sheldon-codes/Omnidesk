import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../../components/auth/auth_components.dart';
import 'reset_password_page_model.dart';

export 'reset_password_page_model.dart';

class ResetPasswordPageWidget extends ConsumerStatefulWidget {
  const ResetPasswordPageWidget({super.key});
  static const routeName = 'ResetPasswordPage';
  static const routePath = '/reset-password';
  @override
  ConsumerState<ResetPasswordPageWidget> createState() =>
      _ResetPasswordPageWidgetState();
}

class _ResetPasswordPageWidgetState
    extends ConsumerState<ResetPasswordPageWidget>
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
    final state = ref.watch(resetPasswordPageProvider);
    final notifier = ref.read(resetPasswordPageProvider.notifier);
    notifier
        .prefillEmail(GoRouterState.of(context).uri.queryParameters['email']);
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
          onPressed: () => context.go('/forgot-password'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back to forgot password',
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 24),
            child: _ProgressDots(current: 2),
          ),
        ],
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
                                  title: 'Create a new\npassword',
                                  subtitle:
                                      'Use the reset code from your email, then choose a strong new password.',
                                ),
                                const SizedBox(height: 30),
                                AuthTextField(
                                  label: 'Email address',
                                  hint: 'agent@company.com',
                                  controller: notifier.emailController,
                                  focusNode: notifier.emailFocusNode,
                                  validator: notifier.validateEmail,
                                  prefixIcon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  onChanged: (_) => notifier.clearError(),
                                  onFieldSubmitted: (_) =>
                                      notifier.tokenFocusNode.requestFocus(),
                                ),
                                const SizedBox(height: 16),
                                AuthTextField(
                                  label: 'Reset code',
                                  hint: 'Paste the code or token',
                                  controller: notifier.tokenController,
                                  focusNode: notifier.tokenFocusNode,
                                  validator: notifier.validateToken,
                                  prefixIcon: Icons.key_outlined,
                                  textInputAction: TextInputAction.next,
                                  onChanged: (_) => notifier.clearError(),
                                  onFieldSubmitted: (_) =>
                                      notifier.passwordFocusNode.requestFocus(),
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
                        label: 'Reset password',
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

  Future<void> _submit(ResetPasswordPageNotifier notifier) async {
    final success = await notifier.submit();
    if (!success || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password updated. You can now sign in.')));
    context.go('/login');
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

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.current});
  final int current;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        2,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: index + 1 == current ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: index + 1 <= current ? theme.primary : theme.alternate,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
