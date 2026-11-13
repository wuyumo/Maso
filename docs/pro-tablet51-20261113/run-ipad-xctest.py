import subprocess,os,json
fd=int(os.environ['MASO_BUILD_LOCK_FD']);phone='CD4768FB-469C-48BE-AB5E-2697DC81C483';target='B7FA50A7-2D85-42F9-83F9-34378020F4A4'
def run(a,**kw):return subprocess.run(a,check=True,pass_fds=(fd,),**kw)
r=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','booted','-j'],text=True));boot={d['udid'] for g in r['devices'].values() for d in g if d['state']=='Booted'};assert not boot-{phone}
restore=phone in boot
if restore:run(['xcrun','simctl','shutdown',phone])
try:
 run(['python3','scripts/low_memory_build.py','sim-prepare',target])
 run(['xcrun','simctl','status_bar',target,'override','--time','9:41','--batteryState','charged','--batteryLevel','100'])
 run(['python3','scripts/low_memory_build.py','xcodebuild','--ui','--','-project','Maso.xcodeproj','-scheme','MasoExerciseUI','-configuration','Debug','-destination','platform=iOS Simulator,id='+target,'-derivedDataPath','build/DerivedData-ProSource48-Simulator','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-collect-test-diagnostics','never','-only-testing:MasoUITests/CoachEquipmentSwapUITests/testMachineChestPressChineseEnglishAndTraditionalNativeSource','-only-testing:MasoUITests/CoachEquipmentSwapUITests/testMachineChestPressRemainingNineNativeRedSources','-resultBundlePath','docs/pro-tablet51-20261113/ipad-native51.xcresult','test-without-building'])
finally:
 subprocess.run(['python3','scripts/low_memory_build.py','sim-release'],pass_fds=(fd,))
 if restore:run(['xcrun','simctl','boot',phone]);run(['xcrun','simctl','bootstatus',phone,'-b'])
