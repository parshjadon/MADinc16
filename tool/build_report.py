"""Build the graduate DOCX from actual, redacted test artifacts."""
import hashlib, json, re, subprocess, textwrap
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

ROOT=Path(__file__).resolve().parent.parent
E=ROOT/'evidence'; OUT=ROOT/'submission'; OUT.mkdir(exist_ok=True)
records=json.loads((E/'test-records.json').read_text())
answers=json.loads((E/'reflections.json').read_text())
proof=json.loads((E/'server-console-export.json').read_text())
events=json.loads((E/'cloud-events.json').read_text())
assert len(records)==15 and all(t['status']=='PASS' for t in records)
for a in answers:
    minimum,maximum=(120,180) if a['id'].startswith('C') else (150,220)
    assert minimum<=len(a['text'].split())<=maximum

fontpath='C:/Windows/Fonts/arial.ttf'
def font(n,bold=False):
    return ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf' if bold else fontpath,n)
def diagram(name,nodes,edges,size):
    im=Image.new('RGB',size,'white'); d=ImageDraw.Draw(im)
    for a,b,label in edges:
        x,y=nodes[a][0]; u,v=nodes[b][0]
        if abs(u-x)>abs(v-y):
            x+=140 if u>x else -140; u+=-140 if u>x else 140
        else: y+=46 if v>y else -46; v+=-46 if v>y else 46
        d.line((x,y,u,v),fill='#597880',width=4)
        import math
        ang=math.atan2(v-y,u-x)
        p1=(u-14*math.cos(ang-.4),v-14*math.sin(ang-.4))
        p2=(u-14*math.cos(ang+.4),v-14*math.sin(ang+.4))
        d.polygon([(u,v),p1,p2],fill='#597880')
        if label:
            lx,ly=(x+u)/2,(y+v)/2
            if any(ra==b and rb==a for ra,rb,_ in edges):
                ly += -24 if (y<v or (y==v and x<u)) else 24
            box=d.textbbox((0,0),label,font=font(21))
            d.rectangle((lx-(box[2]+12)/2,ly-15,lx+(box[2]+12)/2,ly+15),fill='white')
            d.text((lx,ly),label,font=font(21),fill='black',anchor='mm')
    for key,(center,lines) in nodes.items():
        x,y=center; d.rounded_rectangle((x-145,y-46,x+145,y+46),radius=13,fill='#EDF3F2',outline='#597880',width=2)
        d.multiline_text((x,y),'\n'.join(lines),font=font(25,True),fill='black',anchor='mm',align='center',spacing=4)
    im.save(E/f'{name}.png')

diagram('quiz-state-diagram',{
 'signedOut':((180,85),['signedOut']), 'authError':((180,280),['authError']),
 'idle':((560,85),['idle']), 'loading':((940,85),['loading']),
 'requestError':((940,280),['requestError']), 'playing':((1320,85),['playing']),
 'ready':((1320,280),['readyToSubmit']),
}, [('signedOut','idle','UID'),('signedOut','authError','auth error'),('idle','loading','newId'),
 ('loading','playing','5 valid'),('loading','requestError','invalid'),('requestError','loading','retry >= 5 s'),('playing','ready','5 final')],(1510,380))

diagram('cloud-state-diagram',{
 'submitting':((800,80),['submitting']), 'verifying':((800,290),['verifying']),
 'saveUnknown':((220,80),['saveUnknown']), 'permissionDenied':((1380,290),['permissionDenied']),
 'verificationUnavailable':((800,530),['verificationUnavailable']),
 'cloudVerified':((1380,530),['cloudVerified']), 'collision':((220,530),['collision']),
}, [('submitting','saveUnknown','timeout / transport'),('submitting','verifying','acknowledged'),
 ('submitting','collision','mismatch'),('saveUnknown','verifying','settled + reconcile'),
 ('verifying','permissionDenied','denied'),('verifying','verificationUnavailable','network / quota / timeout'),
 ('verificationUnavailable','verifying','manual read'),('permissionDenied','verifying','same-ID read'),
 ('verifying','cloudVerified','valid server snapshot')],(1600,630))

# Screenshot crops remove unrelated review text; they preserve the actual status card.
for name,top,bottom in [('T09-acknowledged-verification-denied',1180,2170),('T09-server-verified',1020,1880)]:
    im=Image.open(E/f'{name}.png')
    crop=im.crop((0,top,im.width,min(bottom,im.height)))
    canvas=Image.new('RGB',(1080,1080),'#F2F6F5')
    canvas.paste(crop,(0,(1080-crop.height)//2))
    canvas.save(E/f'{name}-detail.png')

doc=Document(); section=doc.sections[0]
section.top_margin=Inches(.65); section.bottom_margin=Inches(.65)
section.left_margin=Inches(.7); section.right_margin=Inches(.7)
section.page_width=Inches(8.5); section.page_height=Inches(11)
for sty in ['Normal','Title','Subtitle','Heading 1','Heading 2','Heading 3']:
    s=doc.styles[sty]; s.font.name='Calibri'; s.font.color.rgb=RGBColor(0,0,0)
    s.paragraph_format.space_after=Pt(7)
doc.styles['Normal'].font.size=Pt(10.5)
doc.styles['Normal'].paragraph_format.line_spacing=1.12
doc.styles['Title'].font.size=Pt(25)
doc.styles['Title'].font.bold=True
doc.styles['Heading 1'].font.size=Pt(16)
doc.styles['Heading 2'].font.size=Pt(12)
for sty in ['Heading 1','Heading 2','Heading 3']:
    doc.styles[sty].paragraph_format.keep_with_next=True

def p(text='',style=None): return doc.add_paragraph(text,style)
def h(text,level=1): return doc.add_heading(text,level)
def page(): doc.add_page_break()
def table(headers,rows,widths=None):
    t=doc.add_table(rows=1, cols=len(headers)); t.alignment=WD_TABLE_ALIGNMENT.CENTER
    t.autofit=False
    if widths:
        for i,width in enumerate(widths):
            t.columns[i].width=Inches(width)
            t._tbl.tblGrid.gridCol_lst[i].set(qn('w:w'),str(round(width*1440)))
    for i,c in enumerate(t.rows[0].cells): c.text=headers[i]
    for row in rows:
        for c,text in zip(t.add_row().cells,row): c.text=str(text)
    for ri,row in enumerate(t.rows):
        for ci,c in enumerate(row.cells):
            if widths: c.width=Inches(widths[ci])
            c.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
            pr=c._tc.get_or_add_tcPr()
            border=OxmlElement('w:tcBorders')
            for side in ['top','left','bottom','right']:
                b=OxmlElement('w:'+side); b.set(qn('w:val'),'single'); b.set(qn('w:sz'),'4'); b.set(qn('w:color'),'D9D9D9'); border.append(b)
            pr.append(border)
            sh=OxmlElement('w:shd'); sh.set(qn('w:fill'),'DCE8ED' if ri==0 else ('F4F7F8' if ri%2==0 else 'FFFFFF')); pr.append(sh)
            margins=OxmlElement('w:tcMar')
            for side in ['top','left','bottom','right']:
                e=OxmlElement('w:'+side); e.set(qn('w:w'),'95'); e.set(qn('w:type'),'dxa'); margins.append(e)
            pr.append(margins)
            for para in c.paragraphs:
                para.paragraph_format.space_after=Pt(3); para.paragraph_format.space_before=Pt(3)
                for run in para.runs: run.font.size=Pt(9); run.font.bold=(ri==0)
        row._tr.get_or_add_trPr().append(OxmlElement('w:cantSplit'))
    repeat=OxmlElement('w:tblHeader'); t.rows[0]._tr.get_or_add_trPr().append(repeat)
    return t

def caption(text):
    q=p(text); q.paragraph_format.space_before=Pt(4)
    for r in q.runs:r.font.size=Pt(9)

def picture(name,width=6.7):
    q=p(); q.alignment=WD_ALIGN_PARAGRAPH.CENTER; q.add_run().add_picture(str(E/name),width=Inches(width))

tested=records[0]['commit']; apk=OUT/'ICA16_B_ParshJadon.apk'
apk_hash=hashlib.sha256(apk.read_bytes()).hexdigest()
doc.core_properties.title='Science Signal graduate evidence'
doc.core_properties.author='Parsh Jadon'
doc.core_properties.subject='ICA 16 Class B Flutter and deployed Firebase evidence'
# Remove inherited decorative title rules from the bundled Normal template.
for border in list(doc.styles.element.iter(qn('w:pBdr'))):
    border.getparent().remove(border)
h('Science Signal graduate evidence',0)
p('Parsh Jadon\nIn Class Activity 16  Class B\nGraduate submission  November 17 2026','Subtitle')
p('Science Signal implements a five-question science quiz with authenticated, immutable cloud attempts. The observations below demonstrate real deployed writes, exact server reads, same-ID recovery, authorization failures, and two-client concurrency. All twelve Class B records and three graduate records passed. Local regression tests supplement the cloud observations; injected failures are explicitly identified.')
h('Build and deployment',2)
table(['Item','Verified value'],[
 ('Repository','https://github.com/parshjadon/MADinc16'),
 ('Application commit',tested),('Platform','Android 15 API 35 Google APIs x86 64 emulator  Pixel 6 profile'),
 ('Toolchain','Flutter 3.47.2  Dart 3.13.2  version 1.0.0+1'),
 ('Firebase','inc06-f77f6  (default)  Standard  Native mode  nam5  freeTier true'),
 ('Release','Private RSA signed release  ARM64 and x86 64  installed and cold launched successfully'),
 ('APK SHA256',apk_hash),
], [1.35,5.35])
p('No billing account or paid upgrade was enabled. The 32-bit ARM compiler is blocked by this computer\'s application-control policy; the submitted release supports 64-bit Android devices. Cloud tests used the same application implementation in a temporary debug harness, while the submitted release was built separately without test credentials.')

page();h('Development checkpoints')
logs=subprocess.check_output(['git','log','--reverse','--format=%h|%aI|%s'],cwd=ROOT,text=True).splitlines()
table(['Stage','Commit and time','Retained change'],[(str(i+1),line.split('|')[0]+'\n'+line.split('|')[1],line.split('|',2)[2]) for i,line in enumerate(logs[:4])],[.65,2.05,4.0])
h('Failed first correction',2)
p('The targeted historical-retrieval test initially failed: expected an empty question list, but five questions from the preceding round remained visible. The corrected retrieve method clears questions, selections, and index before requesting another record. The retained failed output is evidence/failed-first-retrieval.txt; the final local suite passes all 21 tests. This prevents an old quiz review from appearing to explain a different historical score.')
h('Exact cloud schema',2)
table(['Field','Type and constraint'],[('schemaVersion','integer 1'),('variant','string B'),('categoryId','integer 17'),('questionCount','integer 5'),('correctCount','integer 0 through 5'),('submittedAt','resolved server timestamp')],[1.8,4.9])
p('Path: users/{authenticated UID}/attempts/{roundId}. The round ID is the document ID only. The transaction reads first, creates only when absent, reuses matching fixed fields, and throws collision on a mismatch. Deployed rules allow owner reads and schema-valid creates; all updates, deletes and unmatched paths are denied. No personal identifiers, question text, credentials or tokens are stored in attempt fields.')

page();h('Actual state machine')
picture('quiz-state-diagram.png')
caption('Quiz and identity phases use the exact RoundPhase names from lib/round_controller.dart.')
picture('cloud-state-diagram.png')
caption('Recovery retains the initiating UID and round ID. The complete transition source is evidence/state-machine.md.')
table(['Guard or variable','Meaning'],[
 ('writeAcknowledged','The original transaction completed successfully; this does not prove a later read succeeded.'),
 ('verified','Set only after exact typed schema, resolved timestamp, server origin and no pending writes are confirmed.'),
 ('operationActive','Owned by the original future until settlement; a UI timeout does not release it.'),
 ('reconciliationRequired','Requires a manual read of the same ID before any uncertain save can be retried.'),
 ('_current(generation, user, id)','Rejects stale callbacks after identity or round changes.'),
 ('canSignOut and canReplay','False while an operation or cloud outcome remains unresolved.'),
],[2.1,4.6])

page();h('The acknowledged write and denied verification')
p('T09 uses a real deployed transaction and a real final server read. Only the first post-commit verification failure is injected. Both screenshots retain the same round suffix. The amber state preserves acknowledgement; the green state adds verified server evidence.')
q=p();q.alignment=WD_ALIGN_PARAGRAPH.CENTER
q.add_run().add_picture(str(E/'T09-acknowledged-verification-denied-detail.png'),width=Inches(3.25))
q.add_run('  ')
q.add_run().add_picture(str(E/'T09-server-verified-detail.png'),width=Inches(3.25))
caption('Actual Android screenshots cropped to the recovery cards. The injection is labelled and deployed rules remain intact. Text, icons and color communicate state together.')
deny=next(t for t in records if t['id']=='T09')
p('Observed transition: submitting → verifying → permissionDenied → verifying → cloudVerified. Round suffix '+deny['roundSuffix']+'. '+deny['timestamp'])
h('Independent deployed record corroboration',2)
p('A read-only export through the project owner\'s existing CLI session independently corroborates the records below. This export is administrative corroboration, not a substitute for the client-authenticated rule tests or Source.server app reads. Source: evidence/server-console-export.json.')
table(['Test','Round suffix','Score','Server submittedAt'],[(v['testId'],'…'+v['roundSuffix'],str(v['fields']['correctCount'])+'/5',v['fields']['submittedAt']) for v in proof],[.5,1.15,.5,4.55])

page();h('Restart retrieval and the original server record')
picture('T07-restarted-server-retrieval.png',3.1)
caption('T07 after process restart: the same user retrieves round …qDeGUO, score 2/5, resolved timestamp, server source and no pending writes. No quiz review or new write is used.')
p('Reproduction: copy the full ID using Copy round ID, force-stop and reopen while online, authenticate as the same authorized user, expand Retrieve a previous result, paste the ID, and choose Read exact server record. Account access is supplied only through an approved private channel. Passwords are not included in this report or public repository.')

page();h('Firebase console proof')
p('The supplied Firebase console screenshot shows the selected deployed attempt ending qDeGUO in the default database. Its six fields match the T06 write and T07 restart retrieval: category 17, score 2, five questions, schema version 1, variant B, and a resolved submission timestamp. The console displays November 17 at 7:56:33 PM; the matching app server read reports 2026-11-18T01:56:33.958Z.')
picture('firebase-console-redacted.png',6.7)
caption('User-provided Firebase console screenshot. Identifier regions are redacted to suffixes; attempt field values are unchanged. The Spark plan indicator is visible at lower left.')
picture('firebase-console-fields.png',3.9)
caption('Detail of the selected attempt. The timezone tail was truncated in the original screenshot; the precise UTC timestamp is independently shown in the app and server export. The empty parent user document does not affect its attempts subcollection.')

page();h('Reproducible test records')
p('Times are UTC and correspond to November 17, 2026 in America/Chicago. Every record includes precondition, action, expected and actual outcome, status, commit, redacted round suffix, and an evidence reference. T03 uses controlled local validation inputs; cloud-required tests use deployed Firebase. Evidence JSON retains machine-readable details.')
for i,t in enumerate(records):
    if i and i%3==0: page();h('Reproducible test records continued')
    h(t['id']+'  '+t['status'],2)
    for label,key in [('Precondition','precondition'),('Action','action'),('Expected','expected'),('Actual','actual')]:
        q=p();q.add_run(label+'  ').bold=True;q.add_run(t[key])
    q=p('Time '+t['timestamp']+'\nCommit '+t['commit']+'  Round suffix '+t['roundSuffix']+'\nEvidence '+t['evidence'])
    for r in q.runs:r.font.size=Pt(8.5)

page();h('Critical thinking responses')
for i,a in enumerate(answers[:6]):
    if i in [2,4]:page();h('Critical thinking responses continued')
    h(a['id']+'  '+a['title'],2);p(a['text'])
    caption(str(len(a['text'].split()))+' words excluding the evidence pair and references')
    if i==0:
        t02=next(e for e in events if e['id']=='T02')['actual']
        pair=t02.split('Encoded: ',1)[1]
        encoded,decoded=pair.split('; decoded: ',1)
        table(['T02 representation','Actual observed string'],[('Encoded',encoded),('Decoded',decoded)],[1.2,5.5])

page();h('AI critique record')
text=(E/'ai-critique.md').read_text(encoding='utf-8')
for para in text.split('\n\n')[1:]:p(para.replace('**','').replace('`',''))

page();h('Graduate investigation')
g01=next(t for t in records if t['id']=='G01');g02=next(t for t in records if t['id']=='G02')
p(g01['actual']);p(g02['actual'])
im=Image.new('RGB',(1500,520),'white'); draw=ImageDraw.Draw(im)
for x,title in [(180,'Client A  score 1'),(750,'Deployed Firestore'),(1320,'Client B  score 4')]:
    draw.text((x,35),title,font=font(27,True),fill='black',anchor='mm')
    draw.line((x,70,x,475),fill='#597880',width=3)
def seq(x,u,y,label):
    draw.line((x,y,u,y),fill='#597880',width=4)
    s=1 if u>x else -1
    draw.polygon([(u,y),(u-s*14,y-7),(u-s*14,y+7)],fill='#597880')
    draw.text(((x+u)/2,y-20),label,font=font(23),fill='black',anchor='mm')
seq(180,750,135,'read shared ID / score 1')
seq(1320,750,215,'read shared ID / score 4')
winner=next(x for x in proof if x['testId']=='G01')['fields']['correctCount']
winner_x=180 if winner==1 else 1320
loser_x=1320 if winner==1 else 180
seq(750,winner_x,310,f'commit acknowledged / score {winner}')
seq(750,loser_x,405,'retry sees mismatch / collision')
draw.text((750,500),f'Final Source.server snapshot: winning score {winner}/5',font=font(24,True),fill='black',anchor='mm')
im.save(E/'graduate-concurrency-diagram.png')
picture('graduate-concurrency-diagram.png')
caption('G01 interleaving with the observed winner. Initial read arrows show competing operations; their drawing order does not establish a global client clock.')
table(['Operation','Before commit','After competing commit'],[
 ('Client A  score 1','Reads shared ID; may observe absence','Commits or retries callback; mismatch becomes collision'),
 ('Client B  score 4','Reads the same ID; may observe absence','Commits or retries callback; mismatch becomes collision'),
 ('Final server read','Uses exact shared reference','Returns the one winning immutable payload'),
 ('G02 independent IDs','References captured separately','Each response checked against its own ID and score'),
],[1.35,2.5,2.85])
for i,a in enumerate(answers[6:]):
    if i==1:page();h('Graduate investigation continued')
    h(a['title'],2);p(a['text']);caption(str(len(a['text'].split()))+' words')

page();h('Reproduction and delivery')
for number,text in enumerate([
 'Install ICA16_B_ParshJadon.apk on a supported 64-bit Android device. Sign in using the authorized test account supplied privately by the project owner.',
 'Start a round, choose one answer to each question, review all five selections and submit once. Confirm the displayed server score, timestamp and redacted ID.',
 'For T09, run a debug build and select permissionDenied in the development-only first-read selector before submitting. Observe the acknowledged amber state, then retry only the server read of the original ID.',
 'For restart retrieval, retain the copied full ID outside the app, force-stop and reopen online, authenticate as the same user and use Retrieve a previous result.',
 'Run flutter analyze and flutter test for local checks. Run the deployed integration suite with private test-account defines for T01–T12 and G01–G03. Never distribute the temporary credential-bearing test APK.',
 'Review README.md for cloud setup, signing and two-client instructions. firestore.rules is the deployed owner-only Class B ruleset. Source code is at the repository URL shown on page one.',
],1):p(str(number)+'. '+text)
h('Assistance disclosure',2)
p('OpenAI Codex substantially assisted with implementation, test design, debugging, writing, and document generation on November 17, 2026. The student should be prepared to explain the actual code and reproduce one failure during an instructor check. Test results, timestamps, screenshots, score winners and failure traces in this report are observations from this implementation; explicit injections and local doubles are distinguished from deployed-cloud proof.')
h('Sources',2)
for s in [
 'Firebase Flutter setup  https://firebase.google.com/docs/flutter/setup',
 'Firestore transactions  https://firebase.google.com/docs/firestore/manage-data/transactions',
 'Firestore server and cache reads  https://firebase.google.com/docs/firestore/query-data/get-data',
 'Open Trivia Database encoding and rate limits  https://opentdb.com/api_config.php',
 'Question content attribution  Open Trivia Database  CC BY SA 4.0',
]:p(s)

security_path=E/'security-remediation.json'
if security_path.exists():
    security=json.loads(security_path.read_text())
    page();h('Private configuration and publishing safeguards')
    p('The Firebase client configuration was moved to ignored private build settings at the project owner\'s request. Previously published client keys were revoked and replaced with keys restricted to the Firebase services used by this app. No billing was enabled. Public APK assets were removed because compiled Firebase clients contain their client key; the updated signed APK is provided locally for submission through the private course portal.')
    p('Actual revalidation: '+security['verification']['result'])
    p('Revalidated at '+security['verification']['time']+'  Original round suffix '+security['verification']['originalSuffix']+'  New verification round suffix '+security['verification']['newSuffix'])
    table(['Safeguard','Verified outcome'],[
      ('Source configuration','Dart reads key values from build settings; actual native/web configuration and private JSON are ignored by Git.'),
      ('Exposed keys','Both previously published Firebase key resources were revoked; the two GitHub alerts were resolved as revoked.'),
      ('Published history','Every published branch and tag was rewritten to remove literal key values. A full reachable-history secret scan passed.'),
      ('Future publishing','Commit/push hooks, a CI history scan, public-document inspection and an APK upload prohibition are installed.'),
      ('Private APK','Rebuilt with replacement configuration and retained only for private course-portal delivery.'),
    ],[1.4,5.3])
    p('The original T01–T12 and G01–G03 records retain their original test-run identifiers as provenance. The history rewrite changed Git commit hashes without changing those recorded observations. evidence/history-rewrite-map.json maps original hashes to sanitized commits; the development checkpoint table uses sanitized history. The configuration revalidation above is a separate, real deployed-cloud observation.')

# A quiet page number supports navigating the evidence during an instructor check.
footer=section.footer.paragraphs[0];footer.alignment=WD_ALIGN_PARAGRAPH.RIGHT
field=OxmlElement('w:fldSimple');field.set(qn('w:instr'),'PAGE');footer._p.append(field)
target=OUT/'ICA16_B_ParshJadon.docx';doc.save(target)
print('Created',target)
print('Answers satisfy every requested word range; 15 factual test records included.')
