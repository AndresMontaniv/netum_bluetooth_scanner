# netum_bluetooth_scanner — working notes for Claude

- Design, sprints and tickets live in an external handoff doc (path in `CLAUDE.local.md`); it is the source of truth.
  Protocol: `doc/protocol.md`. Commands: `doc/commands.md`. Captured packets: `test/fixtures/`.
- Workflow per sprint: Define → Build → Test (hardware) → Analyze. Don't start coding a sprint before its Define is agreed.
- The author does every physical hardware step. Read Android logs yourself with `adb -s <serial> logcat`;
  iOS via `xcrun devicectl device process launch --console --device <udid> <bundle id>` (serials/UDID in `CLAUDE.local.md`).
- Commits: plain messages, NEVER any AI attribution / Co-Authored-By. Commit only when asked; the author pushes and publishes.
- Architecture rules: protocol lives in Dart (`lib/src/protocol`, `lib/src/session`); native code only moves bytes.
  `android/.../core` must not import io.flutter. One in-flight command per device. Never use `neverForLocation`.
- Generated code (`pigeons/` → `*.g.dart`, `NetumApi.g.kt`, `NetumApi.g.swift`): regenerate with
  `dart run pigeon --input pigeons/netum_api.dart`, never hand-edit.
- iOS CocoaPods check (SwiftPM is the default): the example's Xcode project references the plugin as a local package
  (`../../ios/netum_bluetooth_scanner`), which breaks resolution with SwiftPM off. Delete that reference's two lines from
  `project.pbxproj`, `flutter config --no-enable-swift-package-manager`, build/run, then re-enable SwiftPM, `git checkout`
  the pbxproj, xcconfigs and workspace, and delete `Podfile`, `Podfile.lock`, `Pods/`, `.symlinks/`.
- iPhone: always over USB, never wireless. Ask the author to plug it in (and unlock it) before any iOS run.
- Flutter is pinned in both `.tool-versions` (asdf) and `.fvmrc` (FVM): bump them together.
- `.pubignore` replaces `.gitignore` for `pub publish`: when adding a root `.gitignore` rule, mirror it there.
- Simple doc work (test results, summaries) may be delegated to a cheaper model; design/spec stays on the main model.
