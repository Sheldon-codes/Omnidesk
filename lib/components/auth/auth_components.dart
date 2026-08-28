import 'package:flutter/material.dart';

import '../../flutter_flow/flutter_flow_theme.dart';

class AuthPageHeading extends StatelessWidget {
  const AuthPageHeading({
    super.key,
    required this.title,
    required this.subtitle,
  });
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.displaySmall.copyWith(height: 1.12)),
      const SizedBox(height: 12),
      Text(
        subtitle,
        style: theme.bodyMedium.copyWith(
          color: theme.secondaryText,
          height: 1.5,
        ),
      ),
    ]);
  }
}

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.validator,
    required this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
    this.obscureText = false,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? Function(String?) validator;
  final IconData prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final radius = BorderRadius.circular(14);
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        label,
        style: theme.labelMedium.copyWith(
          color: theme.primaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        focusNode: focusNode,
        validator: validator,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        onChanged: onChanged,
        style: theme.bodyMedium.copyWith(color: theme.primaryText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: theme.bodyMedium.copyWith(color: theme.secondaryText),
          prefixIcon: Icon(prefixIcon, color: theme.secondaryText, size: 20),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: theme.secondaryBackground,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          enabledBorder: border(theme.alternate, 1.2),
          focusedBorder: border(theme.primary, 1.7),
          errorBorder: border(theme.error, 1.3),
          focusedErrorBorder: border(theme.error, 1.7),
          errorStyle: theme.bodySmall.copyWith(color: theme.error),
        ),
      ),
    ]);
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: theme.primary,
            disabledBackgroundColor: theme.accent1,
            foregroundColor: theme.primaryBackground,
            shape: const StadiumBorder(),
          ),
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: theme.primaryBackground,
                  ),
                )
              : Text(
                  label,
                  style: theme.bodyMedium.copyWith(
                    color: theme.primaryBackground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.accent1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.error),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: theme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.bodySmall.copyWith(color: theme.error, height: 1.4),
            ),
          ),
        ]),
      ),
    );
  }
}

String? emailValidator(String? value) =>
    value == null || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value.trim())
        ? 'Enter a valid email address'
        : null;

String? passwordValidator(String? value) => value == null || value.length < 8
    ? 'Password must be at least 8 characters'
    : null;

String? requiredValidator(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;
