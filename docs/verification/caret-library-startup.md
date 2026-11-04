# Caret, library management and startup — 2026-11-03

## Behavior

- macOS caret drawing uses the font's CJK body and baseline instead of the full paragraph line height. Line/paragraph spacing and manuscript content are unchanged. The Flutter editor fallback explicitly uses the font size for its caret height. Windows Rich Edit's native caret was not modified or executed on this macOS host.
- Each current/recent work has a more menu with a confirmed deletion action. This is a **local library recycle bin**: the entry leaves the local bookshelf; manuscript files remain at their original location. The confirmation and recycle-bin dialog state this explicitly. Library management opens the recycle bin and restores entries. Opening a retained work folder also restores its entry. No permanent deletion is implemented.
- A current work is flushed before removal. Preferences must save successfully before its entry/session is cleared. Open/delete/restore operations are serialized; quitting waits for these operations. A stable busy overlay keeps the native editor mounted until composition synchronization and saving finish, preserving delayed final input and undo state if opening fails.
- Library location is a compact bottom-right footer outside the scrolling work list. Its full path is available on hover; location changes remain in library management.
- Cold startup draws a vector feather following a curved stroke over 900 ms. It waits for loading, plays once and honors disabled/reduced animations with a static drawing. Already-mounted writing is never replaced by a replay. No new image/video assets or runtime dependencies.

## Measurements and checks

`tool/native_caret_probe.swift` rasterizes the actual production AppKit insertion-point drawing into an isolated bitmap. Before the change, a 20-point font drew a 24/36/52-pixel caret at line heights 1.2/1.8/2.6. Afterwards it draws 20 pixels in all three cases; 16- and 28-point fonts likewise draw 16 and 28 pixels. This is a native drawing check, not OS IME candidate-window acceptance.

Apple API reference used: https://developer.apple.com/documentation/appkit/nstextview (drawInsertionPoint) and NSLayoutManager's font baseline metrics. Native baseline probe also measured Songti's 36-point line baseline at 29 points; this is why merely centering a shorter caret would leave it above the glyph body.

Behavioral regressions cover current-work draft save/restart/restore, non-current deletion preserving the active document, preference-write failure retaining the work, opening during blocked deletion, quitting during blocked deletion, actual confirmation/cancel/restore controls, bottom-right footer placement, startup readiness/reduced motion/no replay, and delayed native composition replies crossing a rendered busy frame.

The read-only reviewer identified two races during implementation: deleting A could clear newly opened B, and a spinner could unload the native view before composition replies. Both have observed failing-then-passing regressions. Final focused review reported no remaining Important/Critical issues.

The independent 99,000 UTF-16-unit scroll/selection probe still passes text preservation, final position, hidden scrollbar, marked `ni` and committed `你好` checks after the caret change. No user manuscript was edited by these probes.

Final full Flutter suite: **106 passed**. Final `flutter analyze --no-pub`: no issues. Raw caret-height results are in `caret-before.txt` and `caret-after.txt`.

`flutter build macos --debug --no-pub` succeeded and the preview was reopened. Native accessibility state showed the startup transition followed by the user's saved 111-word work, and later the updated bookshelf with per-work actions and the location footer. ScreenCaptureKit intermittently returned capture errors during follow-up, so no human-eye caret or full native deletion interaction acceptance is claimed from those attempts. Actual deletion/restoration was exercised only against isolated test works; no user work was removed or typed into.
