import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor_app/core/api/eastmoney_client.dart';

void main() {
  group('EastmoneyClient', () {
    test('secidFromCode shanghai', () {
      expect(EastmoneyClient.secidFromCode('600519'), '1.600519');
      expect(EastmoneyClient.marketFromCode('600519'), 'sh');
    });

    test('secidFromCode shenzhen', () {
      expect(EastmoneyClient.secidFromCode('000001'), '0.000001');
      expect(EastmoneyClient.marketFromCode('300750'), 'sz');
    });

    test('etf codes', () {
      expect(EastmoneyClient.marketFromCode('510300'), 'sh');
      expect(EastmoneyClient.isEtfCode('510300'), isTrue);
      expect(EastmoneyClient.isEtfCode('600519'), isFalse);
    });

    test('invalid code throws', () {
      expect(
        () => EastmoneyClient.marketFromCode('899999'),
        throwsA(isA<EastmoneyException>()),
      );
    });
  });
}
