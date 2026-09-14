# Live game checkpoints

Implemented games: 108, 501, Muushig, Buur, Durak, Canasta, Texas,
Nukh shakhakh, Khodrokh, and 13-card poker. The empty Tsai khuraakh and
Other game placeholders have no game state to synchronize.

- The nine single-state games use `LiveGameState` and their existing save/restore
  codecs. Draft score fields are captured every 400 ms; unchanged payloads do
  not cause writes. Local saves precede network writes.
- An active-table route provides the shared session ID. The current registrar
  can edit; other participants receive snapshots in a read-only view.
- Server transactions compare revisions before writing. A stale writer receives
  the newer server state instead of overwriting it.
- Pending local checkpoints record their base revision. Reopening recovers the
  pending score only when the server revision has not advanced.
- Table membership and the checkpoint ID update atomically with the state.
- 13-card poker retains independent table_1/table_2 state and registrar roles,
  adds automatic local checkpoints, revision checks, stable fingerprints,
  draft inputs and additional game settings to its table snapshots.
- Routes without an active-table ID support local autosave only. Network errors
  appear in the status strip; a connection must initialize before cloud editing.
- The original manual save actions remain available. Live checkpoints remain
  available while the active table exists.

Validation:

```powershell
flutter test --no-pub
flutter build web --release --no-pub
firebase emulators:exec --only firestore --project demo-toocoob-sync --config firebase.sync-test.json "node test/firestore_sync_rules.cjs"
```

The Firestore rules and web build must both be deployed for the hosted app to
use the new session synchronization. Source changes alone do not update the
published app. Test with two participant accounts on the same active table.

Server-side rules tests can also run without an emulator using test/firestore_rules_api.cjs. Set FIREBASE_TOOLS_DIR to the installed firebase-tools directory; the script uses the signed-in Firebase CLI account and synthetic request data.
