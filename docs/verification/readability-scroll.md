# Icon, readability and scroll check — 2026-11-03

Scope: unify control icons, protect theme foreground contrast, reduce manuscript scroll/selection work. Original Songti typography and the leaf brand mark remain.

- Controls now use one Cupertino outline family, including dropdown and submenu arrows. The rendered-widget test excludes only the existing leaf brand mark.
- Palette resolution checks the actual writing, library and panel surfaces, including black/white wallpaper extremes, image wash/dim and minimum editor opacity. Ink, secondary and accent text target at least 4.5:1 after ARGB conversion. Filled buttons choose their foreground separately. User-selected preference values are retained. Recovery/notice banners use an opaque themed surface.
- Normal text contrast reference: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html . This scoped color check is not a full accessibility-conformance claim.
- macOS scroll layout no longer writes the text-container size for every unchanged viewport. Scroll bridge notifications coalesce at 50 ms; a full-state synchronization reads the exact current offset. Selection-only changes send ranges without copying the entire manuscript or notifying the whole workbench.
- AppKit may send intermediate delegate callbacks before marked text settles. Nested insert/mark/unmark operations now synchronize after the outer operation completes. Full state explicitly reports composition, including unchanged-text commits. Windows sends the corresponding full-state flag; its selection path similarly avoids copying text and throttles scroll notifications.

## Isolated native measurement

`tool/native_scroll_probe.swift` instantiates the production AppKit editor in process; it does not open user works. Same host, optimized Swift compilation, 99,000 UTF-16 units, 300 viewport moves and 200 selection notifications (100 range changes plus 100 explicit delegate calls). This is a synchronous synthetic workload, not a display-FPS or human-scroll measurement.

| Measurement | Before | After |
| --- | ---: | ---: |
| Text-container size writes | 300 | 0 |
| Selection batch dispatch | 151.30 ms | 3.39 ms |
| Bridge payload total | 58,234,400 bytes | 22,224 bytes |
| Full-text changed messages from selection | 200 | 0 |
| Scroll messages in the burst | 300 | 1 |

Text and final scroll position were preserved. Additional probe assertions verify `ni` marked at 0..2, followed by committed `你好` with no marked range. This checks AppKit method/delegate ordering, not a real OS candidate-window interaction. Native scrollbar remains hidden.

Raw measurements: `scroll-before.json`, `scroll-after.json` in this directory. The before binary was compiled from the pre-optimization source on the same host. To rerun the current probe, compile NativeNovelEditor.swift and tool/native_scroll_probe.swift together with the SDK's FlutterMacOS framework, then run the resulting executable.

## Verification

- Full Flutter suite: 97 tests passed, including palette extremes, opaque banners, rendered icon family, lightweight selection updates, IME accounting and existing save/menu/AX regressions.
- `flutter analyze --no-pub`: no issues.
- Focused read-only review: no remaining Important/Critical findings.
- macOS debug build succeeded and was reopened. CUA observed consistent outline controls, Songti text, an unchanged 1,349-word saved work, a successful page scroll without a scrollbar, and a readable forest wallpaper theme. Restored the original night theme and reading position afterwards. No manuscript text was entered.
- Final preview-card text uses the same resolved palette; all 17 appearance tests passed again after that small follow-up.
- Windows native compilation, real candidate-window input and human scrolling remain platform/runtime acceptance items; no Windows execution claim is made here.
