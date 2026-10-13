// Typing dates by hand: half-typed years are not dates yet, and never crash.
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/ui/widgets/dialogs.dart';

void main() {
  const today = '2026-10-13';
  test('full and short forms', () {
    expect(parseTypedDate('16/10', today), '2026-10-16');
    expect(parseTypedDate('16/10/2026', today), '2026-10-16');
    expect(parseTypedDate('16-10-26', today), '2026-10-16');
    expect(parseTypedDate('2026-10-16', today), '2026-10-16');
    expect(parseTypedDate('١٦/١٠/٢٠٢٦', today), '2026-10-16');
  });
  test('half-typed or impossible years are not dates', () {
    expect(parseTypedDate('12/02/2', today), isNull);
    expect(parseTypedDate('12/02/202', today), isNull);
    expect(parseTypedDate('12/02/0202', today), isNull);
    expect(parseTypedDate('31/02/2026', today), isNull);
    expect(parseTypedDate('13/13', today), isNull);
  });
}
