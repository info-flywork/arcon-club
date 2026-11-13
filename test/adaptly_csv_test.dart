import 'package:arcon_club/src/ai_tools/adaptly_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('virgüllü, tırnaklı ve BOM\'lu CSV', () {
    final r = adaptlyParseCsv('﻿Mgz,Barkod,Ad\r\n101,869001,"Krem, 50 ml"\n102,869002,"Dedi ki ""merhaba"""\n\n');
    expect(r.length, 2);
    expect(r[0], {'Mgz': '101', 'Barkod': '869001', 'Ad': 'Krem, 50 ml'});
    expect(r[1]['Ad'], 'Dedi ki "merhaba"');
  });

  test('noktalı virgül ayraçlı CSV', () {
    final r = adaptlyParseCsv('BARKOD 1;MARKA\n869001;ARCON\n');
    expect(r.single, {'BARKOD 1': '869001', 'MARKA': 'ARCON'});
  });
}
