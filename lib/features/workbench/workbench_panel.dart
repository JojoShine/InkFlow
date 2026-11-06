import 'package:flutter/material.dart';
import '../appearance/theme_presets.dart';
import '../notes/note_models.dart';
import 'workbench_controller.dart';

class CreativePanelTabs extends StatelessWidget {
  const CreativePanelTabs({super.key, required this.controller});
  final WorkbenchController controller;
  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 0),
      child: Row(
        children: [
          for (var index = 0; index < 4; index++)
            Expanded(
              child: InkWell(
                onTap: () => index == 3
                    ? controller.showAiPanel()
                    : controller.setPanel(NoteKind.values[index]),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color:
                            (index == 3
                                ? controller.aiPanelVisible
                                : !controller.aiPanelVisible &&
                                      controller.panel ==
                                          NoteKind.values[index])
                            ? colors.accent
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    const ['大纲', '角色', '灵感', 'AI'][index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color:
                          (index == 3
                              ? controller.aiPanelVisible
                              : !controller.aiPanelVisible &&
                                    controller.panel == NoteKind.values[index])
                          ? colors.accent
                          : colors.ink,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
