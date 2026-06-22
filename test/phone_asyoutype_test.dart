import 'package:dlibphonenumber/dlibphonenumber.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirror of LoginView._formatAsYouType (private), kept in sync for regression.
String fmt(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '+';
  final formatter = PhoneNumberUtil.instance.getAsYouTypeFormatter('US');
  var out = formatter.inputDigit('+');
  for (final ch in digits.split('')) {
    out = formatter.inputDigit(ch);
  }
  return out.trim();
}

void main() {
  test('as-you-type: empty input stays "+"', () {
    expect(fmt(''), '+');
    expect(fmt('+'), '+');
  });

  test('as-you-type: groups per country and never loses digits', () {
    for (final n in [
      '+8613800138000',
      '+14155550123',
      '+61412345678',
      '+442071838750',
    ]) {
      final out = fmt(n);
      // digits preserved exactly
      expect(out.replaceAll(RegExp(r'[^0-9]'), ''), n.substring(1));
      // international format: starts with '+' and is grouped with a separator
      expect(out.startsWith('+'), isTrue, reason: out);
      expect(
        out.contains(RegExp(r'[\s-]')),
        isTrue,
        reason: 'should group: $out',
      );
    }
  });

  test('as-you-type: CN mobile international grouping', () {
    // Sanity that a known number formats to the expected international layout.
    expect(fmt('+8613800138000'), '+86 138 0013 8000');
  });
}
