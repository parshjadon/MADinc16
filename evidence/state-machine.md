# Implemented round state machine

```mermaid
stateDiagram-v2
    [*] --> signedOut
    signedOut --> authError: signIn rejects
    authError --> idle: authStateChanges supplies UID
    signedOut --> idle: authStateChanges supplies UID
    idle --> loading: startRound / newId once
    loading --> requestError: HTTP or model validation fails
    requestError --> loading: user retry and five-second gate
    loading --> playing: exactly five valid questions
    playing --> playing: choose once / advance after selection
    playing --> readyToSubmit: fifth answer final / freeze score
    readyToSubmit --> submitting: canSubmit and operationActive=false
    submitting --> verifying: transaction acknowledged
    submitting --> saveUnknown: 10-second UI deadline or unavailable
    submitting --> permissionDenied: authorization fails
    submitting --> collision: existing fixed fields differ
    saveUnknown --> verifying: original operation settled / user reconcile
    permissionDenied --> verifying: user retry / same UID and ID
    verifying --> verificationUnavailable: timeout, network, quota or invalid record
    verifying --> permissionDenied: permission-denied
    verifying --> cloudVerified: exact six fields, timestamp, server, no pending writes
    verifying --> readyToSubmit: server absent and no commit acknowledgement
    verifying --> collision: server score differs from frozen score
    verificationUnavailable --> verifying: original read settled / manual same-ID retry
    cloudVerified --> loading: replay and no unresolved operation / new ID
    collision --> loading: user starts genuinely new round
    idle --> verifying: retrieve previous exact ID
```

`identityChanged` increments `_generation` and clears the current round before exposing the new identity. Every completion requires `_current(generation, user, id)`. A stale callback has no transition. Normal sign-out requires `canSignOut`; replay requires `canReplay`. Neither is available while `unresolved` is true. `operationActive` belongs to the original future, not the 10-second waiting future.

# Graduate competing operations

```mermaid
sequenceDiagram
    participant A as Client A score 1
    participant S as Deployed Firestore
    participant B as Client B score 4
    A->>S: transaction read exact shared ID
    B->>S: transaction read exact shared ID
    Note over S: One atomic create wins
    S-->>A: commit or callback retry
    S-->>B: commit or callback retry
    Note over A,B: Losing retry sees different fixed fields and throws collision
    A->>S: Source.server read shared ID
    S-->>A: original winning score and timestamp
```

The schedule does not preselect which client wins. G01 records the observed winner. G02 sends separate IDs concurrently and validates each returned UID, document ID and score. G03 delays delivery of a real A server response, changes actual authentication to B, then releases the old response; `_current` rejects it.
