import 'package:flutter/material.dart';

import '../view_model/home_view_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, HomeViewModel? viewModel})
    : _viewModel = viewModel;

  final HomeViewModel? _viewModel;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget._viewModel == null;
    _viewModel = widget._viewModel ?? HomeViewModel();
  }

  @override
  void dispose() {
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
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            title: Text(_viewModel.title),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  const Icon(Icons.description_outlined, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _viewModel.tagline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
