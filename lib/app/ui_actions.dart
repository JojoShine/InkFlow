import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/storage/operation_journal.dart';

Future<void> uiAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  String? message;
  try {
    await action();
  } on FileSystemException catch (error) {
    message = error.message;
  } on FormatException catch (error) {
    message = error.message;
  } on SaveException catch (error) {
    message = error.toString();
  } on PlatformException catch (error) {
    message = error.message;
  }
  if (message != null && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
          decoration: const InputDecoration(hintText: '输入名称'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(dialogContext, controller.text.trim());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // Dialog closing animation may still paint its field after the route returns.
  await Future<void>.delayed(const Duration(milliseconds: 220));
  controller.dispose();
  return result;
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message, {
  String action = '确定',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

String formatNumber(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);
