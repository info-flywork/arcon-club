import 'package:arcon_club/src/ai_tools/image_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ayar yoksa renk filtresi uygulanmaz', () {
    expect(imageAdjustMatrix(0, 0, 0, false), isNull);
  });

  test('siyah-beyaz: üç kanal aynı ağırlıkları alır', () {
    final m = imageAdjustMatrix(0, 0, 0, true)!;
    expect(m.sublist(0, 3), m.sublist(5, 8));
    expect(m.sublist(0, 3).fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
  });

  test('parlaklık ofset ekler, kontrast ölçekler', () {
    final b = imageAdjustMatrix(50, 0, 0, false)!;
    expect(b[0], closeTo(1, 1e-9));
    expect(b[4], closeTo(64, 1e-9));
    final c = imageAdjustMatrix(0, 100, 0, false)!;
    expect(c[0], closeTo(2, 1e-9));
    expect(c[4], closeTo(-128, 1e-9));
  });
}
