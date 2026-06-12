import 'package:flutter/material.dart';

import '../../../core/model_loading/model_loader.dart';
import '../view_model/home_view_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    HomeViewModel? viewModel,
    ModelLoader? modelLoader,
  }) : _viewModel = viewModel,
       _modelLoader = modelLoader;

  final HomeViewModel? _viewModel;
  final ModelLoader? _modelLoader;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final HomeViewModel _viewModel;
  late final bool _ownsViewModel;
  late final AnimationController _iconAnimation;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget._viewModel == null;
    _viewModel =
        widget._viewModel ?? HomeViewModel(modelLoader: widget._modelLoader);
    _iconAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _viewModel.startLoading();
  }

  @override
  void dispose() {
    _iconAnimation.dispose();
    if (_ownsViewModel) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _StartupLoader(
                    animation: _iconAnimation,
                    title: _viewModel.title,
                    currentTask: _viewModel.currentTask,
                    errorMessage: _viewModel.errorMessage,
                    progress: _viewModel.progress,
                    isReady: _viewModel.isReady,
                    isLoading: _viewModel.isLoading,
                    hasError: _viewModel.hasError,
                    onRetry: _viewModel.retryLoading,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StartupLoader extends StatelessWidget {
  const _StartupLoader({
    required this.animation,
    required this.title,
    required this.currentTask,
    required this.errorMessage,
    required this.progress,
    required this.isReady,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
  });

  final Animation<double> animation;
  final String title;
  final String currentTask;
  final String? errorMessage;
  final double progress;
  final bool isReady;
  final bool isLoading;
  final bool hasError;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = hasError
        ? Icons.error_outline
        : isReady
        ? Icons.check_circle_outline
        : Icons.document_scanner_outlined;
    final iconColor = hasError
        ? colorScheme.error
        : isReady
        ? Colors.green.shade700
        : colorScheme.primary;

    return Column(
      mainAxisAlignment: .center,
      mainAxisSize: .min,
      children: [
        AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final scale = isLoading ? 0.94 + animation.value * 0.12 : 1.0;
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.12),
              border: Border.all(color: iconColor.withValues(alpha: 0.34)),
            ),
            child: Icon(icon, size: 54, color: iconColor),
          ),
        ),
        const SizedBox(height: 22),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 28),
        _LoadingStatus(
          task: currentTask,
          errorMessage: errorMessage,
          hasError: hasError,
        ),
        const SizedBox(height: 14),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _LoadingBar(progress: progress, hasError: hasError),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ],
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.progress, required this.hasError});

  final double progress;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress.clamp(0, 1),
        minHeight: 10,
        color: hasError ? colorScheme.error : colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _LoadingStatus extends StatelessWidget {
  const _LoadingStatus({
    required this.task,
    required this.errorMessage,
    required this.hasError,
  });

  final String task;
  final String? errorMessage;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: .center,
      mainAxisSize: .min,
      children: [
        Text(
          task,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: hasError ? colorScheme.error : null,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            errorMessage!,
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
      ],
    );
  }
}
