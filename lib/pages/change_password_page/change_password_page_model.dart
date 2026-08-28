import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/auth/auth_models.dart';
import '../../services/auth_repository.dart';
import '../../components/auth/auth_components.dart';

part 'change_password_page_model.g.dart';

class ChangePasswordPageState {
  const ChangePasswordPageState({
    this.isSubmitting = false,
    this.currentPasswordVisible = false,
    this.newPasswordVisible = false,
    this.confirmPasswordVisible = false,
    this.errorMessage,
  });
  final bool isSubmitting;
  final bool currentPasswordVisible;
  final bool newPasswordVisible;
  final bool confirmPasswordVisible;
  final String? errorMessage;
  ChangePasswordPageState copyWith({
    bool? isSubmitting,
    bool? currentPasswordVisible,
    bool? newPasswordVisible,
    bool? confirmPasswordVisible,
    Object? errorMessage = _keep,
  }) =>
      ChangePasswordPageState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        currentPasswordVisible:
            currentPasswordVisible ?? this.currentPasswordVisible,
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
class ChangePasswordPageNotifier extends _$ChangePasswordPageNotifier {
  final formKey = GlobalKey<FormState>();
  final currentPasswordController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  final currentPasswordFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();
  final confirmationFocusNode = FocusNode();

  @override
  ChangePasswordPageState build() {
    ref.onDispose(() {
      for (final controller in [
        currentPasswordController,
        passwordController,
        confirmationController
      ]) {
        controller.dispose();
      }
      for (final focus in [
        currentPasswordFocusNode,
        passwordFocusNode,
        confirmationFocusNode
      ]) {
        focus.dispose();
      }
    });
    return const ChangePasswordPageState();
  }

  String? validateCurrentPassword(String? value) => requiredValidator(value);
  String? validatePassword(String? value) => passwordValidator(value);
  String? validateConfirmation(String? value) =>
      value != passwordController.text
          ? 'Passwords do not match'
          : passwordValidator(value);
  void toggleCurrentPasswordVisibility() => state =
      state.copyWith(currentPasswordVisible: !state.currentPasswordVisible);
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
    final result = await ref.read(authRepositoryProvider).changePassword(
          currentPassword: currentPasswordController.text,
          newPassword: passwordController.text,
        );
    if (result is AuthSuccess<void>) {
      currentPasswordController.clear();
      passwordController.clear();
      confirmationController.clear();
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
