# Native screenshot persistence diagnosis (read-only investigation)

- `Maso/MasoApp.swift:25–26` says showcase mock data is not persisted. This is not an effective isolation guard.
- `MasoApp.swift:145–149` runs language `onChange(initial: true)` and calls `dataStore.save()` without excluding `MASO_SHOWCASE_SEED`; lifecycle `:153–155` also calls save. `RootView.swift:1170–1172` calls `flushSave()` on inactive/background without the showcase guard.
- `DataStore.swift:449–458` schedules `writeSnapshotNow()` after0.8s; `:485–497` writes the current mock snapshot using `PersistenceController.shared.save`. `makeMock()` creates an ordinary DataStore, not a read-only store.
- `PersistenceController.swift:73–74` resolves the ordinary app Documents/maso-data.json; `:139` atomically writes it. Only separate explicit Coach chat/swap/onboarding test modes have temporary-file branches (:63–70); the normal marketing navigation route is not one of those modes.

This is a concrete unguarded path consistent with the observed t367 hash change, not a dynamic stack trace or complete reconstruction of that run. There was no full preincident backup, so exact former contents cannot be recovered or claimed restored from a hash. This task does not modify persistence or production App code.

## Evidence preservation and new isolation

A full read-only copy of the CURRENT affected simulator data was preserved in `t369-forensics.local/current-original-simulator-maso-data.json`. It is private runtime evidence, NOT a preincident backup; never commit or upload it. No affected app/container was launched, stopped, reset or overwritten during t369.

The native completion captures use a newly CREATED iPhone17Pro test device and independent app data container, with the unchanged installed3.0.2(51) app bundle. Original data SHA was checked before creation, after install and after captures and remained identical. Only the new task-owned simulator/app were terminated/shut down after capture; no simulator was deleted.

Fresh device: `93FB9C33-FFEC-456A-8C40-491670F97C18`.
Original existing device: `CD4768FB-469C-48BE-AB5E-2697DC81C483` (read-only checks only).
Original data before/after SHA256: `a4574bf3295d5aab039373fe7eff91b1faaadeb1f557ad97479ebacfd76e4f10`.

B uses the existing local marketing `plans` fixture, so the screenshots show real native completed-workout UI with seeded demonstration plans. They are NOT acceptance of an online model's generation quality. No production App changes, AI generation button/consent action, private photo import or purchase were performed.

A later native-owned persistence fix/test-isolation change is separate from this screenshot task.
