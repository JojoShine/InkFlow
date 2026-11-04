# macOS export save-panel permissions

NSSavePanel authorizes the chosen file. The previous RecordStore output created a sibling `<target>.<id>.tmp`, which is outside that grant. A restricted OS sandbox reproduces the exact `Cannot open file` error; writing only the selected file succeeds.

TXT, backup ZIP and share PNG now use `writeSelectedFile`. macOS writes and flushes the authorized file directly; other desktop platforms retain the existing RecordStore replacement. Existing work-folder and symlink guards remain. macOS export replacement is no longer atomic; source manuscripts are not affected.

Verification:
- OS sandbox reproduction/fix: `/tmp/inkflow-export-sandbox-probe.log` (old failure, new PASS).
- 11 focused tests passed: `/tmp/inkflow-export-green.log`.
- Flutter analyze: no issues, `/tmp/inkflow-export-analyze.log`.
- Fresh Flutter debug bundle compiled successfully for darwin: `/tmp/inkflow-export-fixed-flutter-assets`.
- Full macOS debug rebuild passed: `/tmp/inkflow-export-final-build.log`. Official Sparkle 2.9.6 archive verified with SHA256 `52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192`. CocoaPods uses the unmodified official podspec pinned locally to avoid dependency mirror failures.

Application updates and identity migration remain separate incomplete work; their core files are not wired into app startup yet.

Actual rebuilt app verification: exited old app using normal window close, reopened rebuilt app, exported current chapter through NSSavePanel to a unique file in /private/tmp. UI reported `TXT 已导出`; output exists and decodes as UTF-8. Editor remained 1,349 words with saved status.
