"""Redact identifiers in the user-provided console screenshot without changing fields."""
import hashlib,json,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

root=Path(__file__).resolve().parent.parent
source=Path(sys.argv[1])
image=Image.open(source).convert('RGB')
assert image.size==(2528,1328), 'Review redaction regions for a different screenshot size.'
draw=ImageDraw.Draw(image)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',26)
regions=[
 ((817,390,1055,453),'UID …IJfBG2'),
 ((1268,390,1512,453),'…qDeGUO'),
 ((620,487,975,558),'UID …IJfBG2'),
 ((1593,487,2110,557),'Round …qDeGUO'),
 ((1104,651,1468,1327),'Selected: …qDeGUO'),
]
for (left,top,right,bottom),label in regions:
    draw.rectangle((left,top,right,bottom),fill='#222222')
    draw.text((left+10,top+17),label,font=font,fill='#DDDDDD')
    if bottom-top>200:
        draw.text((left+10,top+95),'Other round IDs',font=font,fill='#BBBBBB')
        draw.text((left+10,top+133),'redacted',font=font,fill='#BBBBBB')
out=root/'evidence'
image.save(out/'firebase-console-redacted.png')
image.crop((1515,480,2328,1120)).save(out/'firebase-console-fields.png')
metadata={
 'source':'User-provided Firebase console screenshot',
 'sourceFilename':source.name,
 'sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
 'redactions':'Only UID and document identifier regions; six attempt fields unchanged.',
 'projectDisplayName':'inc06','database':'(default)',
 'testReferences':['T06','T07'], 'uidSuffix':'IJfBG2','roundSuffix':'qDeGUO',
 'observedFields':{'categoryId':17,'correctCount':2,'questionCount':5,'schemaVersion':1,'variant':'B',
   'submittedAt':'Console shows November 17, 2026 at 7:56:33 PM; timezone tail truncated in supplied screenshot.'},
 'matchingServerTimestamp':'2026-11-18T01:56:33.958Z',
}
(out/'console-evidence.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
print('Saved redacted console overview and field detail; source data values are unchanged.')
