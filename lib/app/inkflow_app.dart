import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/appearance/theme_presets.dart';
import '../features/workbench/workbench_controller.dart';
import '../features/workbench/workbench_screen.dart';
import 'desktop_actions.dart';
import 'startup_transition.dart';

class InkFlowApp extends StatelessWidget {
  const InkFlowApp({super.key, required this.controller});
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: 'InkFlow',
      navigatorKey: inkFlowNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: inkTheme(controller.appearance),
      themeAnimationDuration: controller.appearance.animationsEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (controller.focusMode) controller.toggleFocus();
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (!controller.busy) controller.flushAll();
          },
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (!controller.busy) controller.flushAll();
          },
          for (final meta in [true, false]) ...{
            SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: meta,
              control: !meta,
            ): () {
              dispatchDesktopAction(controller, 'open');
            },
            SingleActivator(
              LogicalKeyboardKey.keyN,
              meta: meta,
              control: !meta,
            ): () {
              dispatchDesktopAction(controller, 'newChapter');
            },
            SingleActivator(
              LogicalKeyboardKey.keyN,
              shift: true,
              meta: meta,
              control: !meta,
            ): () {
              dispatchDesktopAction(controller, 'newWork');
            },
            SingleActivator(
              LogicalKeyboardKey.keyI,
              meta: meta,
              control: !meta,
            ): () {
              dispatchDesktopAction(controller, 'import');
            },
            SingleActivator(
              LogicalKeyboardKey.keyE,
              shift: true,
              meta: meta,
              control: !meta,
            ): () {
              dispatchDesktopAction(controller, 'exportChapter');
            },
            SingleActivator(
              LogicalKeyboardKey.keyB,
              shift: true,
              meta: meta,
              control: !meta,
            ): () {
              dispatchDesktopAction(controller, 'backup');
            },
          },
        },
        child: StartupTransition(
          ready: !controller.busy,
          animationsEnabled: controller.appearance.animationsEnabled,
          child: WorkbenchScreen(controller: controller),
        ),
      ),
    ),
  );
}
