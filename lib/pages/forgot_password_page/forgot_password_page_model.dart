import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/auth/auth_models.dart';
import '../../services/auth_repository.dart';
import '../../components/auth/auth_components.dart';

part 'forgot_password_page_model.g.dart';

class ForgotPasswordPageState {
  const ForgotPasswordPageState({
    this.isSubmitting = false,
    this.isSent = false,
    this.errorMessage,
  });
  final bool isSubmitting;
  final bool isSent;
  final String? errorMessage;
  ForgotPasswordPageState copyWith({
    bool? isSubmitting,
    bool? isSent,
    Object? errorMessage = _keep,
  }) =>
      ForgotPasswordPageState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        isSent: isSent ?? this.isSent,
        errorMessage: identical(errorMessage, _keep)
            ? this.errorMessage
            : errorMessage as String?,
      );
  static const _keep = Object();
}

@riverpod
class ForgotPasswordPageNotifier extends _$ForgotPasswordPageNotifier {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final emailFocusNode = FocusNode();

  @override
  ForgotPasswordPageState build() {
    ref.onDispose(() {
      emailController.dispose();
      emailFocusNode.dispose();
    });
    return const ForgotPasswordPageState();
  }

  String? validateEmail(String? value) => emailValidator(value);
  void clearError() {
    if (state.errorMessage != null) state = state.copyWith(errorMessage: null);
  }

  Future<bool> submit() async {
    if (!(formKey.currentState?.validate() ?? false) || state.isSubmitting) {
      return false;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final result = await ref
        .read(authRepositoryProvider)
        .forgotPassword(emailController.text.trim());
    if (result is AuthSuccess<void>) {
      state = state.copyWith(isSubmitting: false, isSent: true);
      return true;
    }
    state = state.copyWith(
      isSubmitting: false,
      errorMessage: (result as AuthFailureResult<void>).failure.displayMessage,
    );
    return false;
  }
}
