# t340 原生/51只读终核阶段回执

时间：2026-11-13T12:14:34.181142+08:00（Asia/Shanghai）

## 1. Duo12：备用设备也失败，0/12新增，按授权停止
- 已确认备用 `7CAEDB18-1E66-490C-AA49-56F5EC72DF86` 原先Shutdown，且无其他xcodebuild/测试占用；只在共享低内存门禁内切换本人17Pro→备用Duo。
- 官方原生内屏配置2007×2853存在，未缩放/改分辨率；启动出现 `Data Migration Failed`，随后XCTest runner启动失败：`NSPOSIXErrorDomain Code64 Host is down / system shell probably crashed`。测试方法未执行，因此没有任何语言断言通过，不接受截图。
- 本人启动的备用Duo已正常关闭，原本人17Pro `CD4768FB-469C-48BE-AB5E-2697DC81C483` 已恢复；只此一台Booted，无遗留xcodebuild/门禁任务。未erase/reset/修用户数据/杀未知进程/关未知设备。
- 专用52FA…和备用7CAE…均失败，不反复重试、不新造设备绕过；需要恢复合法可用的原生Duo运行环境后再补12语。本轮不自行修复运行时或动现有数据，也不以iPad/手机缩放充当Duo。
- 原始源仍48/60：手机12+iPad12+Watch24；Duo缺12。沿用真实DEBUG50kg/185/个人155红态要求；无新增合格Duo源，无法声称每语Duo红态已验。原43历史证据未改，本轮没有改写既有48源。
- 证据：`docs/pro-tablet51-20261113/duo-backup-native51.log`、`duo-backup-native51.xcresult`、`duo-backup-io-before.txt`、`run-duo-backup-xctest.py`。

## 2. 请求的原26目录/命名测试：26/26通过
- `ExerciseSelectionPolicyTests`15项 + `ExerciseLibraryBrowserTests`11项：**26通过/0失败/0跳过**，官方xcresult摘要 `catalog26-summary.json`。
- 复用已获准的DEBUG原生依赖、DerivedData及共享低内存门禁；没有新发行archive、上传或业务修改。
- 历史原轮为25通过/1方法失败（同一方法2个断言失败），证据保留；此前仅测试契约修正为英文显示名或cue组合必须可区分，本轮完整复验其余25项及修正项。没有为了测试改动作名称/目录/算法。
- 日志仍有SwiftUI invalid-frame等启动警告，26契约测试通过不等于全App UI、真机、传感器或所有回归已验；本轮不扩修。
- 证据：`catalog26-recheck.xcresult`、`catalog26-recheck.log`、`run-catalog26.sh`。

## 3. 12语候选：规则一致，未发布；排版待最终编辑
- 12语均≤4000字，保留条件性7天试用/续费条款及隐私/条款链接；都包含UTC月重置、5个支持来源品牌。月度2次共享文字/同目标24小时2调整及安装本地额度等逐语规则已核实，阿拉伯语以双数词表达2，不是漏项。
- 12:11 Asia/Shanghai 官方GET再核公开43的12语description：全部SHA仍与候选来源一致。候选 `applied=false`，未改当前公开43文案，也未写ASC。
- 排版差异：各语UTC句接在Support邮箱后，来源导入段落置于法律页脚后；语义无已知冲突，但应在最终候选编辑时移至额度/导入能力段。此轮只指出，没有改候选文件。
- 证据：`metadata12-audit.json`、`asc43-localizations-live.json`；既有候选 `docs/pro-release51-20261113/store-metadata12-clarified-candidate51.json`。

## 4. 隐私/数据流：具体差异，不代用户改声明
- 本轮重新读取公开主页/隐私政策/App Store页面。主页仍有“coming soon / no analytics”，与已公开3.0.1及自愿启用TelemetryDeck不一致，应更新文案；未发布任何修改。
- 隐私政策已覆盖自愿AI文本/照片处理、转发服务、推荐码随机安装ID及交易归因、可选TelemetryDeck、Apple Health本地处理。尚缺公开链接由设备直接HTTPS取可读正文及本地安装额度的清晰段落。
- App manifest：tracking=false，9类声明；Watch manifest：tracking=false，无CollectedDataTypes，仅SystemBootTime理由35F9.1。两者都与上传51原始指纹一致。不能将Watch本地Health处理误写成Watch服务端收集。
- App Fitness linked+Analytics与公开页unlinked Fitness分析摘要可能属于不同流，不足以证明填错；必须在ASC编辑层逐流核对用途/关联性，不能擅改Health linked或删标识符。DeviceID/PurchaseHistory的DeveloperAdvertising需对应实际可选推荐归因/佣金，而非把本地AI额度说成跨App跟踪。
- 本地额度账本未显示新增服务器收集类别；链接正文/照片AI处理已属既有内容/照片流。不要把“AI无需Masso账号”扩大为整个App无任何购买/推荐标识符。
- 后端供应商/fallback/日志保留仅能引用公开政策声明，客户端不能证实生产后端全部行为；此前403边界维持，不绕过。
- 复核清单及待批准文字在下列草案；没有改网站、manifest或ASC隐私问卷。

### 待父审核的公开文字草案（未应用）
主页：Masso is an offline-first iOS workout tracker. No Masso account is required for core training. Core workout records are stored locally. Optional AI processing, purchases/referrals and usage analytics follow our privacy policy; usage analytics is off until you enable it. Available on the App Store: https://apps.apple.com/app/id6776689750

隐私补充：导入公开链接时，设备会直接向受支持网站请求可读取内容，网站会收到正常连接信息。经你同意进行AI处理时，提取文本可能按AI数据共享政策发送；不包含自动视频／音频转录。AI额度账本保存在本次安装的设备上，与购买恢复和推荐码标识分开；重新安装或换设备可能重置，不能视为跨设备账号权益账本。

## 5. 51状态/边界/精确索引
- 12:07:20 Asia/Shanghai 官方读回51：VALID / APP_STORE_ELIGIBLE，内部READY_FOR_BETA_TESTING、外部READY_FOR_BETA_SUBMISSION；公开3.0.1(43)仍READY_FOR_SALE，没有3.0.2 App Store version slot。不代表已提审或对外上线51。
- HR算法/HealthKit/训练界面/两份动作目录/AI额度/来源读取/App与Watch manifest共9份选定源码SHA全部等于上传51原始指纹：`selected51-source-fingerprints.json`。不需要因本轮新发52。
- 既有48图映射：`docs/pro-tablet51-20261113/ALL-NATIVE-SOURCES.json`，SHA256 `def4efe4e601bc4b85008e5171e794093f85f810b18ed78f581b5874aee62840`。Box仍为 `/workspace/masso-native51-final/SOURCE-MAP.json` 及 `all-native51-review.zip`，不是海报终稿，不碰70c前端。
- 本轮模型调用0、购买0、新发行打包/上传0、提审0、部署0、用户手机安装0。
- 唯一知识库handoff继续使用 `docs/pro-tablet51-20261113/HANDOFF-POINTER.json` 所指本人文件，只追加本阶段；不改根INDEX/context或他人笔记。
