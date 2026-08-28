import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/auth/auth_models.dart';
import '../../services/auth_repository.dart';
import '../../components/auth/auth_components.dart';

part 'reset_password_page_model.g.dart';

class ResetPasswordPageState {
  const ResetPasswordPageState({
    this.isSubmitting = false,
    this.newPasswordVisible = false,
    this.confirmPasswordVisible = false,
    this.errorMessage,
  });
  final bool isSubmitting;
  final bool newPasswordVisible;
  final bool confirmPasswordVisible;
  final String? errorMessage;
  ResetPasswordPageState copyWith({
    bool? isSubmitting,
    bool? newPasswordVisible,
    bool? confirmPasswordVisible,
    Object? errorMessage = _keep,
  }) =>
      ResetPasswordPageState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        newPasswordVisible: newPasswordVisible ?? this.newPasswordVisible,
        confirmPasswordVisible:
            confirmPasswordVisible ?? this.confirmPasswordVisible,
        errorMessage: identical(errorMessage, _keep)
            ? this.errorMessage
            : errorMessage as String?,
      );
  static const _keep = Object();
}

@riverpod
class ResetPasswordPageNotifier extends _$ResetPasswordPageNotifier {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final tokenController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  final emailFocusNode = FocusNode();
  final tokenFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();
  final confirmationFocusNode = FocusNode();

  @override
  ResetPasswordPageState build() {
    ref.onDispose(() {
      for (final controller in [
        emailController,
        tokenController,
        passwordController,
        confirmationController
      ]) {
        controller.dispose();
      }
      for (final focus in [
        emailFocusNode,
        tokenFocusNode,
        passwordFocusNode,
        confirmationFocusNode
      ]) {
        focus.dispose();
      }
    });
    return const ResetPasswordPageState();
  }

  void prefillEmail(String? email) {
    if (email != null && emailController.text.isEmpty) {
      emailController.text = email;
    }
  }

  String? validateEmail(String? value) => emailValidator(value);
  String? validateToken(String? value) => requiredValidator(value);
  String? validatePassword(String? value) => passwordValidator(value);
  String? validateConfirmation(String? value) =>
      value != passwordController.text
          ? 'Passwords do not match'
          : passwordValidator(value);
  void toggleNewPasswordVisibility() =>
      state = state.copyWith(newPasswordVisible: !state.newPasswordVisible);
  void toggleConfirmPasswordVisibility() => state =
      state.copyWith(confirmPasswordVisible: !state.confirmPasswordVisible);
  void clearError() {
    if (state.errorMessage != null) state = state.copyWith(errorMessage: null);
  }

  Future<bool> submit() async {
    if (!(formKey.currentState?.validate() ?? false) || state.isSubmitting) {
      return false;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final result = await ref.read(authRepositoryProvider).resetPassword(
          email: emailController.text.trim(),
          token: tokenController.text.trim(),
          password: passwordController.text,
        );
    if (result is AuthSuccess<void>) {
      state = state.copyWith(isSubmitting: false);
      return true;
    }
    state = state.copyWith(
        isSubmitting: false,
        errorMessage:
            (result as AuthFailureResult<void>).failure.displayMessage);
    return false;
  }
}
