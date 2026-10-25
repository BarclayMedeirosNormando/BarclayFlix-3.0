import 'dart:convert';

import 'package:barclayflix/core/text.dart';
import 'package:barclayflix/features/xtream/data/xtream_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeForSearch ignora acento e caixa', () {
    expect(normalizeForSearch('  Ação Épica  '), 'acao epica');
    expect(normalizeForSearch('NINJA'), 'ninja');
  });

  test('EpgEntry decodifica título base64 e datas unix', () {
    final e = EpgEntry.fromJson({
      'title': base64.encode(utf8.encode('Jornal Nacional')),
      'start_timestamp': '1700000000',
      'stop_timestamp': '1700003600',
    })!;
    expect(e.title, 'Jornal Nacional');
    expect(e.isLiveAt(DateTime.fromMillisecondsSinceEpoch(1700001000 * 1000)), isTrue);
    expect(e.isLiveAt(DateTime.fromMillisecondsSinceEpoch(1700004000 * 1000)), isFalse);
  });

  test('EpgEntry sem datas ou título é descartado', () {
    expect(EpgEntry.fromJson({'title': '', 'start_timestamp': '1', 'stop_timestamp': '2'}), isNull);
    expect(EpgEntry.fromJson({'title': 'x'}), isNull);
  });
}
