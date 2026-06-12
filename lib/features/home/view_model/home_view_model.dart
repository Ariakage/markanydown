import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/model_loading/model_load_progress.dart';
import '../../../core/model_loading/model_loader.dart';
import '../../../data/model_loading/paddle_ocr_vl_model_loader.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({ModelLoader? modelLoader})
    : _modelLoader = modelLoader ?? PaddleOcrVlModelLoader();

  final ModelLoader _modelLoader;
  StreamSubscription<ModelLoadProgress>? _loadingSubscription;
  bool _hasStartedLoading = false;
  bool _isReady = false;
  bool _hasError = false;
  double _progress = 0;
  String _currentTask = '准备加载 PaddleOCR-VL native runtime';
  String? _errorMessage;

  String get title => 'MarkAnyDown';

  String get tagline => 'Convert most files to Markdown format';

  bool get isReady => _isReady;

  bool get isLoading => !_isReady && !_hasError;

  bool get hasError => _hasError;

  double get progress => _progress;

  String get currentTask => _currentTask;

  String? get errorMessage => _errorMessage;

  void startLoading() {
    if (_hasStartedLoading) {
      return;
    }

    _hasStartedLoading = true;
    _loadingSubscription = _modelLoader.load().listen(
      (progress) {
        _progress = progress.progress;
        _currentTask = progress.task;
        notifyListeners();
      },
      onError: (Object error) {
        _hasError = true;
        _isReady = false;
        _errorMessage = error.toString();
        _currentTask = 'PaddleOCR-VL native runtime 加载失败';
        notifyListeners();
      },
      onDone: () {
        if (!_hasError) {
          _progress = 1;
          _isReady = true;
          _currentTask = 'PaddleOCR-VL native runtime 已就绪';
          notifyListeners();
        }
      },
    );
  }

  Future<void> retryLoading() async {
    await _loadingSubscription?.cancel();
    _loadingSubscription = null;
    await _modelLoader.dispose();

    _hasStartedLoading = false;
    _isReady = false;
    _hasError = false;
    _progress = 0;
    _errorMessage = null;
    _currentTask = '准备加载 PaddleOCR-VL native runtime';
    notifyListeners();

    startLoading();
  }

  @override
  void dispose() {
    _loadingSubscription?.cancel();
    unawaited(_modelLoader.dispose());
    super.dispose();
  }
}
