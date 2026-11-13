#!/usr/bin/env python3
"""Run through low_memory_build.py run. Isolated native Watch fixtures, never edits Studio/canonical assets."""
import argparse,pathlib,json,hashlib,plistlib,subprocess,os,datetime,zoneinfo
parser=argparse.ArgumentParser();parser.add_argument('--check-only',action='store_true');parser.add_argument('--locales',default='zh-Hans,en,zh-Hant');args=parser.parse_args()
root=pathlib.Path('docs/pro-watch51-20261113');app=pathlib.Path('build/DerivedData-ProSource48-Simulator/Build/Products/Debug-watchsimulator/MasoWatch.app');watch='3915EE74-D7CB-460F-BB9D-28E841D3A080'
d=plistlib.loads((app/'Info.plist').read_bytes());assert d['CFBundleVersion']=='51' and d['CFBundleShortVersionString']=='3.0.2'
binary=app/'MasoWatch.debug.dylib';b=binary.read_bytes();assert '推胸（器械）'.encode() in b and '卧推（器械）'.encode() not in b and b'MASSO_WATCH_MARKETING_EXERCISE' in b
frozen=json.loads(pathlib.Path('docs/pro-release51-20261113/archive-source-before.json').read_text());assert hashlib.sha256(pathlib.Path('MasoWatch/WatchBridge.swift').read_bytes()).hexdigest()==frozen['MasoWatch/WatchBridge.swift']
locales=args.locales.split(',');assert set(locales)<=set('zh-Hans,en,zh-Hant,ja,ko,es,fr,de,it,pt-BR,ru,ar'.split(','))
print(json.dumps({'version':'3.0.2(51)','artifact':str(app),'dylibSHA256':hashlib.sha256(b).hexdigest(),'targetWatch':watch,'locales':locales,'weightKg':50,'reps':8,'sets':3,'exerciseHeartRate':185,'restHeartRate':160,'unchanged51WatchSource':True,'checkOnly':args.check_only},indent=2),flush=True)
if args.check_only:raise SystemExit(0)
# sim-prepare refuses to close any other running simulator; never bypass the owner gate.
lockfd=int(os.environ['MASO_BUILD_LOCK_FD']);os.fstat(lockfd)
phone='CD4768FB-469C-48BE-AB5E-2697DC81C483' # This workflow's previously idle17Pro fixture simulator.
entries=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','booted','-j'],text=True))
booted={d['udid'] for group in entries['devices'].values() for d in group if d['state']=='Booted'}
assert not (booted-{phone}), 'Another simulator owner is active; do not interrupt it.'
restore_phone=phone in booted
if restore_phone:subprocess.run(['xcrun','simctl','shutdown',phone],check=True)
try:
 subprocess.run(['python3','scripts/low_memory_build.py','sim-prepare',watch],check=True,pass_fds=(lockfd,))
 subprocess.run(['xcrun','simctl','install',watch,str(app)],check=True)
 # watchOS does not support simctl status_bar override; retain actual native clock, never paint/replace it.
 output=root/('native-'+datetime.datetime.now(zoneinfo.ZoneInfo('Asia/Shanghai')).strftime('%H%M%S'));output.mkdir()
 rows=[]
 for locale in locales:
  for mode,bpm,setn in [('exercise',185,1),('rest',160,2)]:
   env=os.environ.copy();env.update({'SIMCTL_CHILD_MASSO_WATCH_PREVIEW':mode,'SIMCTL_CHILD_MASSO_WATCH_MARKETING_HEART':'1','SIMCTL_CHILD_MASSO_WATCH_MARKETING_BPM':str(bpm),'SIMCTL_CHILD_MASSO_WATCH_MARKETING_EXERCISE':'bench_press_machine','SIMCTL_CHILD_MASSO_WATCH_MARKETING_REPS':'8','SIMCTL_CHILD_MASSO_WATCH_MARKETING_SET':str(setn),'SIMCTL_CHILD_MASSO_WATCH_MARKETING_WEIGHT':'50'})
   subprocess.run(['xcrun','simctl','launch','--terminate-running-process',watch,'com.yumowu.maso.watchkitapp','-AppleLanguages','('+locale+')','-AppleLocale',locale],env=env,check=True)
   # Native screenshot round-trips wait for the scene to render; retain all warmups as provenance.
   previous=None;chosen=None
   for i in range(16):
    f=output/(locale+'-'+mode+'-render'+str(i)+'.png');subprocess.run(['xcrun','simctl','io',watch,'screenshot',str(f)],check=True)
    digest=hashlib.sha256(f.read_bytes()).hexdigest();chosen=f
    if len(f.read_bytes())>10000 and digest==previous:break
    previous=digest
   assert chosen.stat().st_size>10000, 'Native scene still blank/loading; no accepted capture.'
   rows.append({'locale':locale,'mode':mode,'source':str(chosen),'SHA256':hashlib.sha256(chosen.read_bytes()).hexdigest(),'weightKg':50,'reps':8,'totalSets':3,'setNumber':setn,'bpm':bpm,'exerciseID':'bench_press_machine','nativeSimulator':True,'physicalSyncProven':False,'needsVisualReview':True})
 (output/'manifest.json').write_text(json.dumps(rows,indent=2));print('MANIFEST',output/'manifest.json',flush=True)
finally:
 subprocess.run(['python3','scripts/low_memory_build.py','sim-release'],check=False,pass_fds=(lockfd,))
 if restore_phone:
  subprocess.run(['xcrun','simctl','boot',phone],check=True)
  subprocess.run(['xcrun','simctl','bootstatus',phone,'-b'],check=True)
