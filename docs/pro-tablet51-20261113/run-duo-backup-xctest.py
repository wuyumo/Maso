import subprocess,os,json
fd=int(os.environ['MASO_BUILD_LOCK_FD']);phone='CD4768FB-469C-48BE-AB5E-2697DC81C483';target='7CAEDB18-1E66-490C-AA49-56F5EC72DF86'
def run(a,**kw):return subprocess.run(a,check=True,pass_fds=(fd,),**kw)
r=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','booted','-j'],text=True));boot={d['udid'] for g in r['devices'].values() for d in g if d['state']=='Booted'};assert not boot-{phone}
restore=phone in boot
if restore:run(['xcrun','simctl','shutdown',phone])
try:
 run(['python3','scripts/low_memory_build.py','sim-prepare',target])
 # Official screenConfig only: turn on native inner mode; no geometry fabrication or pixel scaling.
 import re
 from pathlib import Path
 ports=subprocess.check_output(['xcrun','simctl','io',target,'enumerate'],text=True)
 Path('docs/pro-tablet51-20261113/duo-backup-io-before.txt').write_text(ports)
 blocks=ports.split('Port:');inner=[b for b in blocks if 'Default width: 2007' in b and 'Default height: 2853' in b]
 assert len(inner)==1, 'Unique native Duo2007x2853 inner mode required'
 innerid=re.search(r'UUID: ([A-F0-9-]+)',inner[0]).group(1)
 run(['xcrun','simctl','io',target,'screenConfig','--display='+innerid,'power','on'])
 for b in blocks:
  if b not in inner and 'Default width:' in b and 'Default height:' in b:
   display=re.search(r'UUID: ([A-F0-9-]+)',b).group(1)
   run(['xcrun','simctl','io',target,'screenConfig','--display='+display,'power','off'])
 run(['xcrun','simctl','status_bar',target,'override','--time','9:41','--batteryState','charged','--batteryLevel','100'])
 run(['python3','scripts/low_memory_build.py','xcodebuild','--ui','--','-project','Maso.xcodeproj','-scheme','MasoExerciseUI','-configuration','Debug','-destination','platform=iOS Simulator,id='+target,'-derivedDataPath','build/DerivedData-ProSource48-Simulator','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-collect-test-diagnostics','never','-only-testing:MasoUITests/CoachEquipmentSwapUITests/testMachineChestPressChineseEnglishAndTraditionalNativeSource','-only-testing:MasoUITests/CoachEquipmentSwapUITests/testMachineChestPressRemainingNineNativeRedSources','-resultBundlePath','docs/pro-tablet51-20261113/duo-backup-native51.xcresult','test-without-building'])
finally:
 subprocess.run(['python3','scripts/low_memory_build.py','sim-release'],pass_fds=(fd,))
 if restore:run(['xcrun','simctl','boot',phone]);run(['xcrun','simctl','bootstatus',phone,'-b'])
