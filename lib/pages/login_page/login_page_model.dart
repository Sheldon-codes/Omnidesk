import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/auth_session_controller.dart';
import '../shared/auth_page_scaffold.dart';

part 'login_page_model.g.dart';

class LoginPageState {
  const LoginPageState({
    this.isSubmitting = false,
    this.passwordVisible = false,
    this.errorMessage,
  });
  final bool isSubmitting;
  final bool passwordVisible;
  final String? errorMessage;

  LoginPageState copyWith({
    bool? isSubmitting,
    bool? passwordVisible,
    Object? errorMessage = _keep,
  }) =>
      LoginPageState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        passwordVisible: passwordVisible ?? this.passwordVisible,
        errorMessage: identical(errorMessage, _keep)
            ? this.errorMessage
            : errorMessage as String?,
      );
  static const _keep = Object();
}

@riverpod
class LoginPageNotifier extends _$LoginPageNotifier {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final emailFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();

  @override
  LoginPageState build() {
    ref.onDispose(() {
      emailController.dispose();
      passwordController.dispose();
      emailFocusNode.dispose();
      passwordFocusNode.dispose();
    });
    return const LoginPageState();
  }

  String? validateEmail(String? value) => emailValidator(value);
  String? validatePassword(String? value) => passwordValidator(value);

  void togglePasswordVisibility() =>
      state = state.copyWith(passwordVisible: !state.passwordVisible);

  void clearError() {
    if (state.errorMessage != null) state = state.copyWith(errorMessage: null);
  }

  Future<bool> signIn() async {
    if (!(formKey.currentState?.validate() ?? false) || state.isSubmitting) {
      return false;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final failure = await ref
        .read(authSessionControllerProvider.notifier)
        .login(
            email: emailController.text.trim(),
            password: passwordController.text);
    if (failure != null) {
      state = state.copyWith(
          isSubmitting: false, errorMessage: failure.displayMessage);
      return false;
    }
    state = state.copyWith(isSubmitting: false);
    return true;
  }
}
