# Manuscript edge navigation — 2026-11-04

User scope: manuscript writing area only. A narrow thumb appears while scrolling or hovering at the editor's right edge, supports dragging/track navigation, and fades after one second. A compact return-to-top button appears near the last line at the bottom (up to 48px / 6% of the viewport). Text stays centered at its existing reading width.

- Native scroll events include document ID and generation; stale events are ignored. Jumps change viewport only, not selection, composition or manuscript text.
- Shared right gutter is 44 logical pixels; the return-to-top action is inset 16 px from the right and 14 px from the bottom. Thumb is 4 px, 6 px while hovering/dragging, with a 3 px right inset. Native text containers perform their own internal centering.
- macOS synthetic probe: 99,000 UTF16 characters, 300 scroll steps, no redundant container-size writes; drag to bottom, return top, selection preservation, text preservation, IME draft and commit pass. Evidence: `/tmp/inkflow-scroll-nav-probe.log`.
- Focused Flutter cases exercise fade/hover/drag, delayed native acknowledgements, stale document events, selection after initial metrics, return-top and continued focus-mode writing. Evidence: `/tmp/inkflow-scroll-refinement-green.log`.
- Windows bridge and text insets implemented; actual Windows range/IME behavior requires native-device acceptance.

Share cards: accepted botanical/night PNGs remain byte-identical. The two additional designs now use a pixel window/house/cat scene and film rails/photo/ticket collage. Sharing tests and synthetic PNG inspection pass. No real-manuscript export or formatting was performed for verification.

Final checks: integrated suite154 passed, analyze clean; end-region follow-up group5 passed. Actual macOS window showed a right-edge thumb and returned to the first paragraph.
