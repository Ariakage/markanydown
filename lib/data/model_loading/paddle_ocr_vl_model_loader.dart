import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/model_loading/model_load_progress.dart';
import '../../core/model_loading/model_loader.dart';

class PaddleOcrVlModelLoader implements ModelLoader {
  PaddleOcrVlModelLoader({
    String? runtimeExecutable,
    String? pythonExecutable,
    String? scriptPath,
    String? modelDir,
    String? layoutModelDir,
    String? host,
    int? port,
    Duration timeout = const Duration(minutes: 10),
  }) : _runtimeExecutable =
           runtimeExecutable ??
           Platform.environment['MARKANYDOWN_PADDLEOCR_VL_RUNTIME'] ??
           _defaultRuntimeExecutable(),
       _pythonExecutable =
           pythonExecutable ??
           Platform.environment['MARKANYDOWN_PADDLEOCR_VL_PYTHON'] ??
           _defaultPythonExecutable(),
       _scriptPath =
           scriptPath ??
           Platform.environment['MARKANYDOWN_PADDLEOCR_VL_LOADER'] ??
           _defaultLoaderScriptPath(),
       _modelDir =
           modelDir ??
           Platform.environment['MARKANYDOWN_PADDLEOCR_VL_MODEL_DIR'] ??
           _defaultModelDir(),
       _layoutModelDir =
           layoutModelDir ??
           Platform.environment['MARKANYDOWN_PADDLEOCR_VL_LAYOUT_MODEL_DIR'],
       _host =
           host ??
           Platform.environment['MARKANYDOWN_PADDLEOCR_VL_HOST'] ??
           '127.0.0.1',
       _port =
           port ??
           int.tryParse(
             Platform.environment['MARKANYDOWN_PADDLEOCR_VL_PORT'] ?? '',
           ) ??
           8765,
       _timeout = timeout;

  final String? _runtimeExecutable;
  final String _pythonExecutable;
  final String _scriptPath;
  final String _modelDir;
  final String? _layoutModelDir;
  final String _host;
  final int _port;
  final Duration _timeout;
  Process? _process;
  StreamSubscription<String>? _stderrSubscription;
  bool _isDisposed = false;

  @override
  Stream<ModelLoadProgress> load() async* {
    if (_process != null) {
      yield const ModelLoadProgress(
        task: 'PaddleOCR-VL native runtime 已就绪',
        progress: 1,
      );
      return;
    }

    _isDisposed = false;

    yield const ModelLoadProgress(
      task: '准备加载 PaddleOCR-VL native runtime',
      progress: 0.04,
    );

    final command = _runtimeExecutable ?? _pythonExecutable;
    final arguments = _runtimeExecutable == null
        ? [await _requireScriptPath(), ..._buildArguments()]
        : _buildArguments();

    if (_runtimeExecutable != null &&
        !await File(_runtimeExecutable).exists()) {
      throw ModelLoadException(
        '未找到 PaddleOCR-VL native runtime: $_runtimeExecutable',
      );
    }

    yield const ModelLoadProgress(
      task: '启动 PaddleOCR-VL native 进程',
      progress: 0.1,
    );

    if (_isDisposed) {
      throw const ModelLoadException('PaddleOCR-VL native runtime 已停止');
    }

    final process = await Process.start(command, arguments, runInShell: false);
    _process = process;
    if (_isDisposed) {
      await _terminateProcess(process);
      throw const ModelLoadException('PaddleOCR-VL native runtime 已停止');
    }

    final stderr = StringBuffer();
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write);

    try {
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final event = _parseRuntimeLine(line);
        if (event != null) {
          yield event.progress;

          if (event.name == 'ready') {
            return;
          }
        }
      }

      final exitCode = await process.exitCode.timeout(_timeout);
      if (identical(_process, process)) {
        _process = null;
      }
      throw ModelLoadException(
        'PaddleOCR-VL native runtime 已退出，退出码 $exitCode: ${stderr.toString().trim()}',
      );
    } catch (_) {
      if (identical(_process, process)) {
        _process = null;
      }
      await _terminateProcess(process);
      await _stderrSubscription?.cancel();
      _stderrSubscription = null;
      rethrow;
    }
  }

  Future<String> _requireScriptPath() async {
    final script = File(_scriptPath);
    if (!await script.exists()) {
      throw ModelLoadException('未找到 PaddleOCR-VL 加载脚本: ${script.path}');
    }
    return script.path;
  }

  List<String> _buildArguments() {
    final layoutModelDir =
        _layoutModelDir ?? _join([_modelDir, 'PP-DocLayoutV2']);

    return [
      '--host',
      _host,
      '--port',
      '$_port',
      '--pipeline-version',
      _environmentValue('MARKANYDOWN_PADDLEOCR_VL_PIPELINE_VERSION') ?? 'v1',
      '--parent-pid',
      '$pid',
      if (Directory(_modelDir).existsSync()) ...['--model-dir', _modelDir],
      if (Directory(layoutModelDir).existsSync()) ...[
        '--layout-model-dir',
        layoutModelDir,
      ],
      if (_environmentValue('MARKANYDOWN_PADDLEOCR_VL_DEVICE')
          case final device?) ...[
        '--device',
        device,
      ],
      if (_environmentValue('MARKANYDOWN_PADDLEOCR_VL_ENGINE')
          case final engine?) ...[
        '--engine',
        engine,
      ],
      if (_environmentValue('MARKANYDOWN_PADDLEOCR_VL_VL_BACKEND')
          case final vlBackend?) ...[
        '--vl-rec-backend',
        vlBackend,
      ],
      if (_environmentValue('MARKANYDOWN_PADDLEOCR_VL_VL_SERVER_URL')
          case final vlServerUrl?) ...[
        '--vl-rec-server-url',
        vlServerUrl,
      ],
    ];
  }

  _RuntimeEvent? _parseRuntimeLine(String line) {
    try {
      final payload = jsonDecode(line);
      if (payload is! Map<String, Object?>) {
        return null;
      }

      final task = payload['task'];
      final progress = payload['progress'];
      if (task is! String || progress is! num) {
        return null;
      }

      return _RuntimeEvent(
        name: payload['event'] as String?,
        progress: ModelLoadProgress(
          task: task,
          progress: progress.toDouble().clamp(0, 1),
        ),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    final process = _process;
    _process = null;
    if (process != null) {
      await _terminateProcess(process);
    }
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;
  }

  Future<void> _terminateProcess(Process process) async {
    final exitCode = process.exitCode;
    process.kill();

    try {
      await exitCode.timeout(const Duration(seconds: 5));
      return;
    } on TimeoutException {
      if (!Platform.isWindows) {
        process.kill(ProcessSignal.sigkill);
      } else {
        process.kill();
      }
    }

    try {
      await exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // The OS will reclaim resources when the parent app exits. The native
      // runtime also watches the parent PID as a second cleanup path.
    }
  }

  static String? _environmentValue(String name) {
    final value = Platform.environment[name];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  static String _defaultLoaderScriptPath() {
    return _firstExistingPath([
      for (final root in _resourceRoots()) ...[
        _join([root, 'tools', 'paddleocr_vl', 'native_runtime.py']),
        _join([root, 'runtime', 'paddleocr_vl', 'native_runtime.py']),
      ],
    ]);
  }

  static String _defaultModelDir() {
    return _firstExistingPath([
      for (final root in _resourceRoots()) ...[
        _join([root, 'models', 'paddleocr_vl', 'PaddleOCR-VL']),
        _join([root, 'PaddleOCR-VL']),
      ],
    ]);
  }

  static String? _defaultRuntimeExecutable() {
    final executableName = Platform.isWindows
        ? 'markanydown_paddleocr_vl_runtime.exe'
        : 'markanydown_paddleocr_vl_runtime';
    const runtimeDirectoryName = 'markanydown_paddleocr_vl_runtime';
    final path = _firstExistingPath([
      for (final root in _resourceRoots()) ...[
        _join([
          root,
          'runtime',
          'paddleocr_vl',
          runtimeDirectoryName,
          executableName,
        ]),
        _join([root, 'paddleocr_vl', runtimeDirectoryName, executableName]),
        _join([root, 'runtime', 'paddleocr_vl', executableName]),
        _join([root, 'paddleocr_vl', executableName]),
      ],
    ]);

    return File(path).existsSync() ? path : null;
  }

  static String _defaultPythonExecutable() {
    final executableName = Platform.isWindows ? 'python.exe' : 'python';
    final venvPath = _firstExistingPath([
      for (final root in _resourceRoots()) ...[
        if (Platform.isWindows)
          _join([root, '.venv_paddleocr', 'Scripts', executableName])
        else
          _join([root, '.venv_paddleocr', 'bin', executableName]),
      ],
    ]);

    if (File(venvPath).existsSync()) {
      return venvPath;
    }

    return Platform.isWindows ? 'python' : 'python3';
  }

  static List<String> _resourceRoots() {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final roots = <String>[
      Directory.current.path,
      executableDir,
      _join([executableDir, 'data']),
    ];

    if (Platform.isMacOS) {
      roots.add(_join([executableDir, '..', 'Resources']));
    }

    return roots;
  }

  static String _firstExistingPath(List<String> paths) {
    for (final path in paths) {
      if (File(path).existsSync() || Directory(path).existsSync()) {
        return path;
      }
    }
    return paths.first;
  }

  static String _join(List<String> parts) {
    return [
      for (final part in parts) part.replaceAll(RegExp(r'[/\\]+$'), ''),
    ].join(Platform.pathSeparator);
  }
}

class _RuntimeEvent {
  const _RuntimeEvent({required this.progress, this.name});

  final ModelLoadProgress progress;
  final String? name;
}

class ModelLoadException implements Exception {
  const ModelLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}
