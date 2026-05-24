import 'package:appflowy/plugins/document/presentation/local_file/local_file_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkedFileInfo', () {
    test('roundtrips through JSON correctly', () {
      final info = const LinkedFileInfo(
        path: '/Users/test/project/README.md',
        type: 'markdown',
        linkedAt: 1712345678901,
      );

      final json = info.toJson();
      final restored = LinkedFileInfo.fromJson(json);

      expect(restored.path, '/Users/test/project/README.md');
      expect(restored.type, 'markdown');
      expect(restored.linkedAt, 1712345678901);
    });

    test('handles minimal JSON', () {
      final info = LinkedFileInfo.fromJson({'path': '/tmp/note.txt'});
      expect(info.path, '/tmp/note.txt');
      expect(info.type, 'markdown'); // default
      expect(info.linkedAt, isNull);
    });

    test('tryFromJsonString is safe on bad input', () {
      expect(LinkedFileInfo.tryFromJsonString(null), isNull);
      expect(LinkedFileInfo.tryFromJsonString('not json'), isNull);
      expect(LinkedFileInfo.tryFromJsonString('{}')?.path, '');
    });
  });
}
