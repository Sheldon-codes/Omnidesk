import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/change_password_page/change_password_page_model.dart';
import 'package:omnidesk_agent/pages/forgot_password_page/forgot_password_page_model.dart';
import 'package:omnidesk_agent/pages/login_page/login_page_model.dart';
import 'package:omnidesk_agent/pages/reset_password_page/reset_password_page_model.dart';

void main() {
  test('generated page providers expose isolated initial state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(loginPageProvider).isSubmitting, isFalse);
    expect(container.read(loginPageProvider).errorMessage, isNull);
    expect(container.read(forgotPasswordPageProvider).isSent, isFalse);
    expect(container.read(resetPasswordPageProvider).isSubmitting, isFalse);
    expect(container.read(changePasswordPageProvider).isSubmitting, isFalse);
    expect(container.read(changePasswordPageProvider).errorMessage, isNull);
  });
}
