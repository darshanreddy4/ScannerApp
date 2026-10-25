import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/app/di.dart';
import 'package:scanvault/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:scanvault/features/ocr/domain/recognize_document_text.dart';
import 'package:scanvault/features/ocr/domain/text_repository.dart';
import 'package:scanvault/features/settings/presentation/settings_cubit.dart';

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
