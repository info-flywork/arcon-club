import 'package:arcon_core/src/talk/talk_share_kinds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('konum mesajı yazılır ve geri okunur (adresli ve adressiz)', () {
    final a = talkLocationLine(talkLocationBody(41.0123456, 29.0234567, 'Kadıköy, İstanbul'))!;
    expect(a.lat, closeTo(41.012346, 1e-6));
    expect(a.lng, closeTo(29.023457, 1e-6));
    expect(a.address, 'Kadıköy, İstanbul');
    final b = talkLocationLine(talkLocationBody(-33.5, 151.25, ''))!;
    expect(b.address, '');
    expect(talkLocationLine('📍 Konum burada'), isNull);
  });

  test('anket yazılır ve geri okunur; bozuk biçim anket sayılmaz', () {
    final p = talkPollLine(talkPollBody('Toplantı ne zaman?', ['Pazartesi', 'Salı', 'Çarşamba']))!;
    expect(p.question, 'Toplantı ne zaman?');
    expect(p.options, ['Pazartesi', 'Salı', 'Çarşamba']);
    expect(talkPollLine('📊 Tek seçenek\n1. A'), isNull);
    expect(talkPollLine('📊 Sıra bozuk\n1. A\n3. B'), isNull);
    expect(talkPollLine('merhaba'), isNull);
  });
}
