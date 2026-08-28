import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../shared/auth_page_scaffold.dart';
import 'login_page_model.dart';

export 'login_page_model.dart';

class LoginPageWidget extends ConsumerStatefulWidget {
  const LoginPageWidget({super.key});
  static const routeName = 'LoginPage';
  static const routePath = '/login';
  @override
  ConsumerState<LoginPageWidget> createState() => _LoginPageWidgetState();
}

class _LoginPageWidgetState extends ConsumerState<LoginPageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, .8, curve: Curves.easeOut),
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero)
        .animate(CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, .8, curve: Curves.easeOutCubic),
    ));
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final radius = BorderRadius.circular(14);
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: theme.bodyMedium.copyWith(
        color: theme.secondaryText,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: theme.secondaryBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: border(theme.alternate, 1),
      focusedBorder: border(theme.primary, 1.4),
      errorBorder: border(theme.error, 1.2),
      focusedErrorBorder: border(theme.error, 1.4),
      errorStyle: theme.bodySmall.copyWith(color: theme.error, fontSize: 12),
    );
  }

  Widget _label(String text) {
    final theme = FlutterFlowTheme.of(context);
    return Text(
      text,
      style: theme.bodyMedium.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: theme.primaryText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginPageProvider);
    final notifier = ref.read(loginPageProvider.notifier);
    final theme = FlutterFlowTheme.of(context);
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          surfaceTintColor: theme.primaryBackground,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 56,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeIn,
            child: SlideTransition(
              position: _slideUp,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 36),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Form(
                          key: notifier.formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Align(
                                alignment: Alignment.center,
                                child: FlutterLogo(size: 100),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Welcome Back!',
                                textAlign: TextAlign.center,
                                style: theme.headlineMedium.copyWith(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  color: theme.primaryText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Stay on top of every customer conversation, from first message to resolution.',
                                textAlign: TextAlign.center,
                                style: theme.bodyMedium.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: theme.secondaryText,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 22),
                              _label('Email address*'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: notifier.emailController,
                                focusNode: notifier.emailFocusNode,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => notifier.clearError(),
                                onFieldSubmitted: (_) =>
                                    notifier.passwordFocusNode.requestFocus(),
                                validator: notifier.validateEmail,
                                style: theme.bodyMedium.copyWith(
                                  fontSize: 14,
                                  color: theme.primaryText,
                                ),
                                decoration: _fieldDecoration(
                                  hint: 'agent@company.com',
                                ),
                              ),
                              const SizedBox(height: 14),
                              _label('Password*'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: notifier.passwordController,
                                focusNode: notifier.passwordFocusNode,
                                obscureText: !state.passwordVisible,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) => notifier.clearError(),
                                onFieldSubmitted: (_) => _submit(notifier),
                                validator: notifier.validatePassword,
                                style: theme.bodyMedium.copyWith(
                                  fontSize: 14,
                                  color: theme.primaryText,
                                ),
                                decoration: _fieldDecoration(
                                  hint: 'Enter your password',
                                  suffixIcon: Semantics(
                                    button: true,
                                    label: state.passwordVisible
                                        ? 'Hide password'
                                        : 'Show password',
                                    child: IconButton(
                                      onPressed:
                                          notifier.togglePasswordVisibility,
                                      tooltip: state.passwordVisible
                                          ? 'Hide password'
                                          : 'Show password',
                                      icon: Icon(
                                        state.passwordVisible
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: theme.secondaryText,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: state.isSubmitting
                                      ? null
                                      : () => context.go('/forgot-password'),
                                  child: Text(
                                    'Forgot Password?',
                                    style: theme.bodyMedium.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: theme.primaryText,
                                    ),
                                  ),
                                ),
                              ),
                              if (state.errorMessage != null) ...[
                                AuthErrorBanner(state.errorMessage!),
                                const SizedBox(height: 18),
                              ] else
                                const SizedBox(height: 18),
                              SizedBox(
                                height: 54,
                                child: FilledButton(
                                  onPressed: state.isSubmitting
                                      ? null
                                      : () => _submit(notifier),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: theme.primary,
                                    disabledBackgroundColor: theme.accent1,
                                    foregroundColor: theme.primaryBackground,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: state.isSubmitting
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: theme.primaryBackground,
                                          ),
                                        )
                                      : Text(
                                          'Sign in',
                                          style: theme.bodyMedium.copyWith(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: theme.primaryBackground,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(LoginPageNotifier notifier) async {
    final success = await notifier.signIn();
    if (success && mounted) context.go('/home');
  }
}
