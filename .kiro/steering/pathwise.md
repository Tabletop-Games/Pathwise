# Pathwise working rules

- There is no custom backend. Do not add Cloud Run, Firestore, custom APIs or backend-issued identities. Progress syncs through Play Games Saved Games (`docs/cloud-saves.md`).
- Gameplay needs a confirmed internet connection through `ConnectivityService`. Do not add per-screen network checks.
- Economy and progress live in the device save and the cloud envelope. Economy that changed on both sides is never merged automatically.
- Keep `progressKeys` in `lib/cloud/cloud_save_format.dart` in step with what counts as progress. Bump `cloudSaveVersion` when the payload shape changes.
- Run `dart format .`, `flutter analyze` and `flutter test` before committing. Analyzer infos fail CI here.
- The archived backend is on `archive/server-authoritative-backend`. Do not restore it to `main`.
