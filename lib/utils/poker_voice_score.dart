int? parsePokerVoiceScore(String text) {
  var value = text.trim().toLowerCase().replaceFirst(RegExp(r'\s+оноо$'), '');
  if (value == 'хожсон' || value == 'хожлоо') return 0;
  var sign = 1;
  if (value.startsWith('хасах ')) { sign = -1; value = value.substring(6); }
  if (value.startsWith('нэмэх ')) value = value.substring(6);
  final number = int.tryParse(value);
  if (number != null) return sign * number;
  if (value == 'зуу' || value == 'зуун') return sign * 100;
  if (value.startsWith('зуун ')) {
    final remainder = parsePokerVoiceScore(value.substring(5));
    if (remainder != null && remainder > 0 && remainder < 100) return sign * (100 + remainder);
  }
  const units = {'тэг':0,'нэг':1,'хоёр':2,'гурав':3,'дөрөв':4,'тав':5,'зургаа':6,'долоо':7,'найм':8,'ес':9};
  const tens = {'арав':10,'арван':10,'хорь':20,'хорин':20,'гуч':30,'гучин':30,'дөч':40,'дөчин':40,'тавь':50,'тавин':50,'жар':60,'жаран':60,'дал':70,'далан':70,'ная':80,'наян':80,'ер':90,'ерэн':90};
  if (units.containsKey(value)) return sign * units[value]!;
  if (tens.containsKey(value)) return sign * tens[value]!;
  final words = value.split(' ');
  if (words.length == 2 && tens.containsKey(words[0]) && units.containsKey(words[1])) return sign * (tens[words[0]]! + units[words[1]]!);
  return null;
}
