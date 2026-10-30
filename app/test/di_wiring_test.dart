import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:doculoom/features/ocr/domain/recognize_document_text.dart';
import 'package:doculoom/features/ocr/domain/text_repository.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';

void main() {
  test('the real dependency graph builds the screens that use text recognition', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    sl.reset();
    configureDependencies();

    expect(sl<DocumentsCubit>, returnsNormally);
    expect(sl<SettingsCubit>, returnsNormally);
    expect(sl<TextRepository>, returnsNormally);
    expect(sl<RecognizeDocumentText>, returnsNormally);
  });
}
