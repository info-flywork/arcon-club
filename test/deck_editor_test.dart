import 'package:arcon_club/src/ai_tools/deck_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  test('sayfadaki yazı öğeleri bulunur, SVG ve görseller atlanır', () {
    final doc = html_parser.parse('''
<section class="slide"><div class="wrap"><h1>Başlık <em>vurgulu</em></h1>
<ul><li>Bir</li><li>İki<br>satır</li></ul><svg><text>x</text></svg><img src="a.jpg">
<div class="card"><p>Kart</p><span>etiket</span></div></div></section>''');
    final els = deckTextElements(doc.querySelector('.slide')!);
    expect(els.map(deckReadText).toList(), ['Başlık vurgulu', 'Bir', 'İki\nsatır', 'Kart', 'etiket']);
  });

  test('yazı değişince <br> ile yazılır, değişmezse biçim korunur', () {
    final doc = html_parser.parse('<section class="slide"><h2>Merhaba <b>dünya</b></h2></section>');
    final h = doc.querySelector('h2')!;
    deckWriteText(h, 'Merhaba dünya');
    expect(h.innerHtml, 'Merhaba <b>dünya</b>');
    deckWriteText(h, 'Yeni\nsatır');
    expect(h.innerHtml, 'Yeni<br>satır');
  });
}
