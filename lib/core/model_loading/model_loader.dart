import 'model_load_progress.dart';

abstract interface class ModelLoader {
  Stream<ModelLoadProgress> load();

  Future<void> dispose();
}
