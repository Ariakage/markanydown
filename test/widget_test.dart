// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:markanydown/app.dart';
import 'package:markanydown/core/model_loading/model_load_progress.dart';
import 'package:markanydown/core/model_loading/model_loader.dart';

void main() {
  testWidgets('MarkAnyDown app renders', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MarkAnyDownApp(modelLoader: _FakeModelLoader()));
    await tester.pump();

    expect(find.text('MarkAnyDown'), findsOneWidget);
    expect(find.text('PaddleOCR-VL native runtime 已就绪'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
  });
}

class _FakeModelLoader implements ModelLoader {
  @override
  Stream<ModelLoadProgress> load() async* {
    yield const ModelLoadProgress(
      task: 'PaddleOCR-VL native runtime 已就绪',
      progress: 1,
    );
  }

  @override
  Future<void> dispose() async {}
}
