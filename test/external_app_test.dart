import 'package:arcon_club/src/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modül, backend\'den gelen mağaza uygulaması bilgisini okur', () {
    final m = ArconModule.fromJson({
      'key': 'arconnect',
      'external': {'ios_scheme': 'arconnect://', 'ios_store_url': 'https://apps.apple.com/app/id6812633145', 'android_package': 'com.arcon.arconnect', 'android_store_url': ''},
    });
    expect(m.external?.iosScheme, 'arconnect://');
    expect(m.external?.iosStoreUrl, 'https://apps.apple.com/app/id6812633145');
    expect(m.external?.androidStoreUrl, '');
    expect(ArconModule.fromJson({'key': 'todo'}).external, isNull);
  });
}
