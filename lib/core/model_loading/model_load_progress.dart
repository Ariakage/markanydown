class ModelLoadProgress {
  const ModelLoadProgress({required this.task, required this.progress})
    : assert(progress >= 0 && progress <= 1);

  final String task;
  final double progress;
}
