import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'phone_page_model.dart';

/// The page-local dial task. PhonePageWidget owns navigation and state; this
/// widget owns the keypad presentation and interaction surface.
class PhoneDialPadWidget extends StatelessWidget {
  const PhoneDialPadWidget({
    super.key,
    required this.state,
    required this.theme,
    required this.onBack,
    required this.onDigit,
    required this.onDelete,
    required this.onClear,
    required this.onCall,
  });

  final PhonePageState state;
  final FlutterFlowTheme theme;
  final VoidCallback onBack;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final display = _formatNumber(state.dialedNumber);
    final contact = state.matchedContact;
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back to Phone',
                onPressed: onBack,
                icon: Icon(IconsaxPlusBroken.arrow_left_2,
                    color: theme.primaryText, size: 26),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Text(
              display.isEmpty ? 'Enter number' : display,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleLarge.override(
                color:
                    display.isEmpty ? theme.secondaryText : theme.primaryText,
                fontSize: 35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Text(
              state.dialedNumber.isEmpty
                  ? 'Dial a number'
                  : contact?.title ?? 'Not in contacts',
              style: theme.bodyMedium.override(
                color: theme.secondaryText,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: _DialPadGrid(
              theme: theme,
              onDigit: onDigit,
              onCall: onCall,
              onDelete: onDelete,
              onClear: onClear,
              canDelete: state.dialedNumber.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(String value) {
    if (value.length <= 3) return value;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(value[i]);
    }
    return buffer.toString();
  }
}

class _DialPadGrid extends StatelessWidget {
  const _DialPadGrid({
    required this.theme,
    required this.onDigit,
    required this.onCall,
    required this.onDelete,
    required this.onClear,
    required this.canDelete,
  });

  final FlutterFlowTheme theme;
  final ValueChanged<String> onDigit;
  final VoidCallback onCall;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final bool canDelete;

  static const _keys = [
    ('1', ' '),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var row = 0; row < 5; row++)
              Expanded(
                child: Row(
                  children: [
                    for (var column = 0; column < 3; column++)
                      Expanded(
                        child: _buildCell(row, column),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _buildCell(int row, int column) {
    if (row < 4) {
      final key = _keys[row * 3 + column];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: _DialKey(
          digit: key.$1,
          letters: key.$2,
          theme: theme,
          onTap: () => onDigit(key.$1),
        ),
      );
    }
    if (column == 1) return _CallKey(theme: theme, onTap: onCall);
    if (column == 2 && canDelete) {
      return _DialActionKey(
        theme: theme,
        onTap: onDelete,
        onLongPress: onClear,
      );
    }
    return const SizedBox.shrink();
  }
}

class _CallKey extends StatelessWidget {
  const _CallKey({required this.theme, required this.onTap});

  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Call',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: Tooltip(
            message: 'Call',
            child: Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.success,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 25),
              ),
            ),
          ),
        ),
      );
}

class _DialKey extends StatelessWidget {
  const _DialKey({
    required this.digit,
    required this.letters,
    required this.theme,
    required this.onTap,
  });

  final String digit;
  final String letters;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: letters.isEmpty ? 'Digit $digit' : 'Digit $digit, $letters',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(44),
          overlayColor:
              WidgetStatePropertyAll(theme.primary.withValues(alpha: .10)),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: theme.titleLarge.override(
                    color: theme.primaryText,
                    fontSize: 27,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (letters.isNotEmpty)
                  Text(
                    letters,
                    style: theme.bodySmall.override(
                      color: theme.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.2,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _DialActionKey extends StatelessWidget {
  const _DialActionKey({
    required this.theme,
    required this.onTap,
    required this.onLongPress,
  });

  final FlutterFlowTheme theme;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Delete last digit',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(44),
          overlayColor:
              WidgetStatePropertyAll(theme.primary.withValues(alpha: .10)),
          child: SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: Icon(Icons.backspace_outlined,
                  color: theme.secondaryText, size: 21),
            ),
          ),
        ),
      );
}
