#!/usr/bin/env python3
"""Run under low_memory_build.py run. Native screenshots only; never edit Studio/canonical assets or app containers."""
import argparse,subprocess,os,json,pathlib,hashlib,plistlib,re,datetime,zoneinfo
from PIL import Image
ap=argparse.ArgumentParser();ap.add_argument('--family',choices=['ipad','duo'],required=True);args=ap.parse_args()
root=pathlib.Path('docs/pro-tablet51-20261113');family=args.family
phone='CD4768FB-469C-48BE-AB5E-2697DC81C483'
target={'ipad':'B7FA50A7-2D85-42F9-83F9-34378020F4A4','duo':'52FA8324-79C2-4FF2-A101-FA91C96C46CB'}[family]
expected={'ipad':(2064,2752),'duo':(2007,2853)}[family]
app=pathlib.Path('build/DerivedData-ProSource48-Simulator/Build/Products/Debug-iphonesimulator/Maso.app')
info=plistlib.loads((app/'Info.plist').read_bytes());assert info['CFBundleVersion']=='51' and info['CFBundleShortVersionString']=='3.0.2'
fd=int(os.environ['MASO_BUILD_LOCK_FD']);os.fstat(fd)
def call(*a,env=None):return subprocess.check_output(['xcrun','simctl',*a],text=True,env=env).strip()
r=json.loads(call('list','devices','booted','-j'));booted={d['udid'] for g in r['devices'].values() for d in g if d['state']=='Booted'}
assert not (booted-{phone}), 'Another owner simulator is active; do not interrupt.'
restore=phone in booted
if restore:call('shutdown',phone)
rows=[];out=root/'native'/family;out.mkdir(parents=True,exist_ok=True)
try:
 subprocess.run(['python3','scripts/low_memory_build.py','sim-prepare',target],check=True,pass_fds=(fd,))
 call('install',target,str(app))
 port=None
 if family=='duo':
  blocks=call('io',target,'enumerate').split('Port:');matches=[b for b in blocks if 'Default width: 2007' in b and 'Default height: 2853' in b]
  assert len(matches)==1, 'Duo native inner display2007x2853 not uniquely available'
  port=re.search(r'UUID: ([A-F0-9-]+)',matches[0]).group(1)
  (root/'duo-cli-io-before.txt').write_text(call('io',target,'enumerate'))
  call('io',target,'screenConfig','--display='+port,'power','on')
  for block in blocks:
   if block not in matches and 'Default width:' in block and 'Default height:' in block:
    outer=re.search(r'UUID: ([A-F0-9-]+)',block).group(1)
    call('io',target,'screenConfig','--display='+outer,'power','off')
 call('status_bar',target,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100')
 for locale in ['en','zh-Hans','zh-Hant','ja','ko','es','fr','de','it','pt-BR','ru','ar']:
  web='zh' if locale=='zh-Hans' else locale;folder=out/web;folder.mkdir(exist_ok=True)
  env=os.environ.copy();env.update({'SIMCTL_CHILD_MASO_EXERCISE_UI_TEST_SCENE':'stable-player','SIMCTL_CHILD_MASO_MARKETING_PLAYER':'1','SIMCTL_CHILD_MASO_MARKETING_EXERCISE_ID':'bench_press_machine','SIMCTL_CHILD_MASO_WORKOUT_HEART_FIXTURE':'1','SIMCTL_CHILD_MASO_WORKOUT_HEART_CARD':'1','SIMCTL_CHILD_MASO_TEST_HEART_LIMIT':'155','SIMCTL_CHILD_MASO_TEST_HEART_BPM':'185'})
  launch=call('launch','--terminate-running-process',target,'com.yumowu.maso','-maso.selectedLanguage',locale,'-AppleLanguages','('+locale+')','-AppleLocale',locale,env=env)
  accepted=None;redFrames=0
  for i in range(28):
   frame=folder/('warmup'+str(i)+'.png');cmd=['io',target,'screenshot']+(['--display='+port] if port else [])+[str(frame)];call(*cmd)
   image=Image.open(frame).convert('RGB');assert image.size==expected,(image.size,expected)
   # Wait for the real native red overlay at plain transport margins. This READS pixels; it never alters them.
   probes=[image.getpixel((int(image.width*.035),int(image.height*y))) for y in [.72,.78,.84,.89]]
   red=sum(1 for rr,gg,bb in probes if rr-gg>=10 and rr-bb>=10)>=3
   redFrames=redFrames+1 if red else 0
   if redFrames>=2 and frame.stat().st_size>100000:accepted=frame;break
  assert accepted is not None, 'Native red player did not appear on '+family+' '+locale+'; no source accepted. Duo launch alone may not move app to inner display.'
  dest=folder/'player-heart-warning.png';dest.write_bytes(accepted.read_bytes())
  row={'locale':web,'family':family,'source':str(dest),'SHA256':hashlib.sha256(dest.read_bytes()).hexdigest(),'dimensions':list(expected),'nativeDevice':target,'nativeDisplayPort':port,'launchReceipt':launch,'capturedAt':datetime.datetime.now(zoneinfo.ZoneInfo('Asia/Shanghai')).isoformat(),'exerciseID':'bench_press_machine','sets':3,'reps':8,'weightKg':50,'heartBpm':185,'personalLimitBpm':155,'nativeRedBackgroundPixelProbePassed':True,'nativeAXRedAssertionOnThisDevice':False,'equivalent12PhoneLanguagesAXRedProven':True,'nativeSimulator':True,'physicalSyncProven':False,'pixelsEdited':False,'needsParentVisualReview':True}
  rows.append(row);(root/(family+'-manifest.json')).write_text(json.dumps(rows,ensure_ascii=False,indent=2));print('CAPTURED',family,web,row['SHA256'],flush=True)
finally:
 subprocess.run(['python3','scripts/low_memory_build.py','sim-release'],check=False,pass_fds=(fd,))
 if restore:call('boot',phone);call('bootstatus',phone,'-b')
print('COMPLETE',family,len(rows),flush=True)
