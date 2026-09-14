import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/bank_details.dart';

void main() {
  test('stored bank details round trip into QR without losing leading zeros', () {
    const details = BankDetails(bank: ' Банк ', iban: 'mn 00123', account: '001234');
    final restored = BankDetails.fromMap(details.toMap());
    expect(restored.complete, isTrue);
    expect(restored.qrText, 'Банк: Банк\nIBAN: MN00123\nДансны дугаар: 001234');
  });
  test('missing profile data does not enable QR', () {
    expect(BankDetails.fromMap(null).complete, isFalse);
    expect(BankDetails.fromMap({'bank': 'Банк'}).complete, isFalse);
  });
}
