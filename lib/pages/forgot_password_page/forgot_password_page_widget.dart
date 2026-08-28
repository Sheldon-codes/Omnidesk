import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../../components/auth/auth_components.dart';
import 'forgot_password_page_model.dart';

export 'forgot_password_page_model.dart';

class ForgotPasswordPageWidget extends ConsumerStatefulWidget {
  const ForgotPasswordPageWidget({super.key});
  static const routeName = 'ForgotPasswordPage';
  static const routePath = '/forgot-password';
  @override
  ConsumerState<ForgotPasswordPageWidget> createState() =>
      _ForgotPasswordPageWidgetState();
}

class _ForgotPasswordPageWidgetState
    extends ConsumerState<ForgotPasswordPageWidget>
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
    final state = ref.watch(forgotPasswordPageProvider);
    final notifier = ref.read(forgotPasswordPageProvider.notifier);
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
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back to sign in',
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
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: state.isSent
                                ? _Confirmation(
                                    email: notifier.emailController.text)
                                : Form(
                                    key: notifier.formKey,
                                    child: _EmailForm(
                                      notifier: notifier,
                                      errorMessage: state.errorMessage,
                                      onSubmitted: () => _submit(notifier),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _BottomAction(
                isSent: state.isSent,
                isLoading: state.isSubmitting,
                onSubmit: () => _submit(notifier),
                email: notifier.emailController.text,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(ForgotPasswordPageNotifier notifier) async {
    await notifier.submit();
  }
}

class _EmailForm extends StatelessWidget {
  const _EmailForm({
    required this.notifier,
    required this.errorMessage,
    required this.onSubmitted,
  });

  final ForgotPasswordPageNotifier notifier;
  final String? errorMessage;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthPageHeading(
            title: 'Forgot\npassword?',
            subtitle:
                'Enter your work email and we’ll send secure reset instructions.',
          ),
          const SizedBox(height: 34),
          AuthTextField(
            label: 'Email address',
            hint: 'agent@company.com',
            controller: notifier.emailController,
            focusNode: notifier.emailFocusNode,
            validator: notifier.validateEmail,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onChanged: (_) => notifier.clearError(),
            onFieldSubmitted: (_) => onSubmitted(),
          ),
          const SizedBox(height: 12),
          _ResetGuidance(),
          if (errorMessage != null) ...[
            const SizedBox(height: 18),
            AuthErrorBanner(errorMessage!),
          ],
        ],
      );
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.isSent,
    required this.isLoading,
    required this.onSubmit,
    required this.email,
  });

  final bool isSent;
  final bool isLoading;
  final VoidCallback onSubmit;
  final String email;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SizedBox(
              width: double.infinity,
              child: AuthPrimaryButton(
                label: isSent ? 'Enter reset code' : 'Reset Password',
                isLoading: !isSent && isLoading,
                onPressed: isSent
                    ? () => context.go(
                          '/reset-password?email=${Uri.encodeComponent(email)}',
                        )
                    : onSubmit,
              ),
            ),
          ),
        ),
      );
}

class _ResetGuidance extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, size: 17, color: theme.primary),
      const SizedBox(width: 8),
      Expanded(
          child: Text(
              'For security, this message is shown whether or not the email exists.',
              style: theme.bodySmall
                  .copyWith(color: theme.secondaryText, height: 1.45))),
    ]);
  }
}

class _Confirmation extends StatelessWidget {
  const _Confirmation({required this.email});
  final String email;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
        key: const ValueKey('confirmation'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
              width: 56,
              height: 56,
              decoration:
                  BoxDecoration(color: theme.accent1, shape: BoxShape.circle),
              child:
                  Icon(Icons.mark_email_read_outlined, color: theme.primary)),
          const SizedBox(height: 24),
          const AuthPageHeading(
              title: 'Check your inbox',
              subtitle:
                  'If an account exists for this email, reset instructions are on their way.'),
          const SizedBox(height: 16),
          Text(email,
              style: theme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700, color: theme.primaryText)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Back to sign in')),
        ]);
  }
}
