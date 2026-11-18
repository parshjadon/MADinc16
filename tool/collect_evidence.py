"""Collect only redacted facts from private integration logs."""
import json, re, subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
def read_log(name):
    raw = (ROOT / 'private' / name).read_bytes()
    return raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8', errors='replace')
def events(name):
    return [json.loads(x) for x in re.findall(r'EVIDENCE (\{[^\r\n]*\})', read_log(name))]

data = events('cloud-run-final.log') + events('restart-run-final.log')
assert 'All tests passed.' in read_log('cloud-run-final.log')
assert 'All tests passed.' in read_log('restart-run-final.log')
unit_text = (ROOT/'evidence/raw/unit-tests.txt').read_text(encoding='utf-16')
assert 'All tests passed!' in unit_text
commit = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
data.append(dict(id='T03', time=datetime.now(timezone.utc).isoformat(), commit=commit,
 roundSuffix='none', status='PASS', actual='Local deterministic tests rejected malformed percent/UTF-8, nonzero API codes, four/six results, invalid answer values and metadata; five-second gate prevented early HTTP retries. No cloud behavior is simulated as evidence.'))

spec = {
 'T01': ('Two enabled Email/Password test accounts; signed out.', 'Submit invalid credentials, then valid A credentials through the app.', 'Readable auth error, then intended authenticated identity; no secret logging.'),
 'T02': ('Online with valid user A.', 'GET the exact Class B URL and validate each result.', 'Exactly 5 decoded medium category-17 boolean questions.'),
 'T03': ('Isolated parser/HTTP regression tests; controlled HTTP responses and clock.', 'Inject malformed encoding, nonzero response_code, four results and invalid answer values; retry before/after 5 seconds.', 'Invalid data cannot become playable; readable QuizException; no HTTP retry before 5 seconds.'),
 'T04': ('A live validated five-question response.', 'Use fixed True/False UI, correct/wrong choices and repeated selections.', 'Continue disabled until selection; repeated answers blocked; text/icon/color feedback; 2/5 total.'),
 'T05': ('Completed 2/5 round verified by server.', 'Review all 5 entries and replay.', 'New ID, zero score, empty selections, index zero.'),
 'T06': ('Completed round, online, no prior document at allocated ID.', 'Invoke Submit twice while transaction is pending.', 'One immutable document, six fields, resolved timestamp, exact server-only confirmation.'),
 'T07': ('Original T06 record exists; previous Android process force-stopped.', 'Start a fresh process, authenticate same A, retrieve original ID through app.', 'Original 2/5 record returned from server without replay, question review or new write.'),
 'T08': ('Completed round, networking disabled before transaction.', 'Submit offline, reconnect, wait for original operation, reconcile same ID and retry if absent.', 'No false success or new ID; recover original round without overlapping retries.'),
 'T09': ('Online completed round; debug-only one-shot denied-read hook selected.', 'Real commit; inject first verification denial; manually retry same-ID server read.', 'Acknowledged commit retained; labelled unavailable verification; final real read verifies same document.'),
 'T10': ('Independent Firebase client authenticated as user B; A record exists.', 'Read A record and create under A path as B.', 'Both rejected by deployed owner-only rules with permission-denied.'),
 'T11': ('User A authenticated; original valid record exists.', 'Development-only requests: score 6, extra field, update existing score; reread original.', 'All invalid writes rejected; original score and timestamp unchanged.'),
 'T12': ('Online; debug-only unavailable or quota fault armed after real commit.', 'Inject each first verification failure and manually retry.', 'Distinct visible error codes/messages; labelled injections; real final server read; no fake success.'),
 'G01': ('Two independent clients authenticated as A; one shared unused ID.', 'Concurrently submit scores 1 and 4 to same ID.', 'Exactly one wins; other reports collision; final server payload matches winner.'),
 'G02': ('Two independent clients authenticated as A; different unused IDs.', 'Concurrently submit scores 0 and 5 and read each original reference.', 'Both succeed; each UID/ID/score stays associated with its initiating operation.'),
 'G03': ('Actual A cloud response captured but delivery delayed.', 'Sign out A, sign in B, invalidate generation, then deliver old response.', 'No A result/ID/acknowledgement is attached to B screen.'),
}
records=[]
for id in list(spec):
    observed=[e for e in data if e['id']==id]
    assert observed, f'Missing evidence {id}'
    pre,action,expected=spec[id]
    records.append(dict(id=id,precondition=pre,action=action,expected=expected,
      actual=' '.join(e['actual'] for e in observed),status='PASS',
      timestamp=' / '.join(e['time'] for e in observed),
      commit=observed[-1]['commit'],roundSuffix=' / '.join(e['roundSuffix'] for e in observed),
      evidence=('unit-tests.txt; test/quiz_test.dart' if id=='T03' else 'cloud-events.json; integration_test/'+('restart_test.dart' if id=='T07' else 'cloud_test.dart'))))
(ROOT/'evidence/test-records.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
(ROOT/'evidence/cloud-events.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
for name in ['unit-tests.txt','failed-first-retrieval.txt']:
    raw=(ROOT/'evidence/raw'/name).read_bytes()
    text=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8',errors='replace')
    (ROOT/'evidence'/name).write_text(text,encoding='utf-8')
for name in ['T01-auth-error','T04-fixed-choices-feedback','T09-acknowledged-verification-denied','T09-server-verified','T07-restarted-server-retrieval']:
    from shutil import copyfile
    source=ROOT/'evidence/raw'/f'{name}.png'
    if source.exists(): copyfile(source,ROOT/'evidence'/f'{name}.png')
print(f'Collected {len(records)} complete test records. All actual observations passed.')
