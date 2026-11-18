# AI assistance and critique record

Tool: OpenAI Codex, November 17, 2026. This project used substantial AI assistance in code, tests, debugging, writing and document assembly. This record critiques an initial design response generated during that work. The fictional prompt below contains no private code, account identifiers or credentials.

**Prompt:** “A Flutter app stores a fictional score under players/{uid}/runs/{runId}. Its write succeeds, but the next server read is permission-denied. Propose the recovery state and retry behavior, including a ten-second UI timeout.”

**Initial response excerpt:** “Keep the committed run ID. Show ‘Write acknowledged; verification unavailable’ and let Retry read that same ID. A timeout should show an uncertain result rather than claim the write failed.”

**Claim 1:** A denied confirmation read does not undo the successful commit. T09 checks a real transaction, injects only the first read failure, then verifies the original deployed document through a real server read. Local regression `T09 acknowledged commit plus denied verification retains ID and retries only read` additionally counts one commit and two reads.

**Claim 2:** A UI timeout is uncertainty, not cancellation. Regression `T08 commit timeout retains operation lock until original settles` delays a future past the UI deadline, checks that additional submit/reconcile calls do not overlap it, releases that same future, and recovers the original ID. The live T08 observation disables Firestore networking before submission and reconnects without replacing the ID.

**Limitation:** The initial response does not define who owns the lock after the deadline, or what happens if authentication changes while a future is pending. Simply unlocking in the timeout handler can start a second operation. Merely checking whichever user is current at completion can put A's response on B's screen.

**Revised design:** The original operation owns `operationActive` until settlement. Timeout sets `reconciliationRequired`; retry is a same-ID server read, and an absent record allows a transaction only after the original future has settled. The frozen attempt captures the initiating UID and ID. `_generation` and `_current` discard stale responses. G03 exercises that guard with an actual cloud response delayed across an actual account change. These details make the candidate's useful wording operationally defensible.
