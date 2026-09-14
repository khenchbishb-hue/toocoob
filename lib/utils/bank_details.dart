class BankDetails {
  const BankDetails({this.bank = '', this.iban = '', this.account = ''});
  final String bank;
  final String iban;
  final String account;

  bool get complete => bank.trim().isNotEmpty && iban.trim().isNotEmpty && account.trim().isNotEmpty;
  Map<String, String> toMap() => {'bank': bank.trim(), 'iban': iban.replaceAll(RegExp(r'\s'), '').toUpperCase(), 'account': account.trim()};
  factory BankDetails.fromMap(dynamic value) {
    if (value is! Map) return const BankDetails();
    return BankDetails(bank: value['bank'] is String ? value['bank'] : '',
      iban: value['iban'] is String ? value['iban'] : '',
      account: value['account'] is String ? value['account'] : '');
  }
  String get qrText {
    final data = toMap();
    return 'Банк: ${data['bank']}\nIBAN: ${data['iban']}\nДансны дугаар: ${data['account']}';
  }
}
