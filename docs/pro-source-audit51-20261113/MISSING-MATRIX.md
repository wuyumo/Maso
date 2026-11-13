# 51素材剩余源：确切缺项矩阵

核验：2026-11-13 Asia/Shanghai。只读原始PNG51张，Apple Vision OCR逐图取证，SHA256逐图未变；不是264图全重截。

## 数字缺项（每行均已找到原图，不是文件丢失）

| 语言 | iPhone 原图→目标 | iPad 原图→目标 | Duo 原图→目标 | Watch训练/休息 原图→目标 |
|---|---|---|---|---|
| zh | 本轮不重截；已有51独立源 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 已交付50kg/185、50kg/160 |
| zh-Hant | 本轮不重截；已有51独立源 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 已交付50kg/185、50kg/160 |
| en | 本轮不重截；已有51独立源 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 已交付50kg/185、50kg/160 |
| ja | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| ko | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| es | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| fr | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| de | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| it | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| pt-BR | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| ru | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |
| ar | 60kg/150→50kg/185 | 60kg/185→50kg/185 | 60kg/185→50kg/185 | 60kg/185、60kg/160→50kg/185、50kg/160 |

总计必要原生补拍51张：9手机 + 24 iPad/Duo + 18 Watch；仅第03页相关真实源，不触其他页、43原图和前端。每张完整路径/原SHA/识别原文在missing-matrix.json及ocr-results.json。

## 名称与真实本地化

iPad/Duo四张简繁原图仍为卧推/臥推，当前catalog正确为推胸；这是旧素材，不需修改51产品。Watch剩余9语中，日语旧fixture省略“機械”，另外8语DEBUG marketingName退为全英文；真实Watch正常同步采用手机传入exerciseName，不据此推断产品运行时缺翻译。

必须按真实catalog，而非自造全本地化：
- ja: チェストプレス (マシン · 機械)
- ko: 가슴 압박 (머신)
- es: Chest Press (Máquina)
- fr: Presse thoracique (Machine)
- de: Brustpresse (Maschine)
- it: Chest Press (Macchina)
- pt-BR: Prensa do tórax (Máquina)
- ru: Чест-пресс (Тренажёр · машина)
- ar: Chest Press (جهاز)

西/意/阿catalog动作主名称实际仍Chest Press，设备词已本地化；葡语Prensa do tórax、韩语가슴 압박为既有文本。本轮不自改为新的产品翻译。

## 捕获设备与明确门禁

- iPad原图2064×2752；Duo原图2007×2853。Duo必须用折叠内屏原生IO port（旧受支持脚本capture_plan_a_scenes.py:92–100）；禁止拿手机/iPad拉伸冒充。
- 开始时iPhone17Pro及另一iPhone18Pro 0BB4FEB8-0DC7-499F-91BD-AF307E342143同时booted。未获该18Pro所有权，依AGENTS单模拟器规则不关闭、不抢占、不开始UI捕获。没有运行中的xcodebuild。
- 旧capture脚本默认会写canonical且备份用户模拟器Documents，本轮不执行；后续独立输出并采用隔离DEBUG host，不能写canonical或触用户资料。

## 新发现：已有51手机三语可能未呈现红色警告

现有51三语手机原图185bpm，但底色非旧43警告红；尚不能直接声称警告态已通过。源ExerciseLibraryUITestHost.swift:320–324：MARKETING_PLAYER开启后每5秒又送128bpm，覆盖显式185输入。应仅DEBUG fixture持续尊重MASO_TEST_HEART_BPM，并复核阈值155（旧43原生警告态使用155，当前51测试180）和真实warning状态后再接受为“超限变红”素材。不是产品心率逻辑故障结论；不得P红底或改51发行逻辑。

本短阶段没有新发行构建、安装、模型请求、购买、ASC写入、生产操作或前端更改。

## 本阶段已准备的最小修正（尚未新原生补拍）

- WatchBridge.swift仅#if DEBUG marketingName新增9语实际catalog文字；保留西/意/阿真实混合命名，不自译产品名。
- ExerciseLibraryUITestHost.swift仅DEBUG循环尊重显式MASO_TEST_HEART_BPM；没传时仍128，发行产品代码不变。
- capture-watch51.py新增独立--app；对每个请求语言先检查Debug二进制确含catalog名称，陈旧英语fallback包拒绝采纳；仍保留51版本、源指纹、单模拟器和非空原生渲染门禁。
- Release有效代码与已上传51基准逐字相同，详见release-fixture-guard.json。新Debug Watch包尚未构建，UI捕获未开始，原生补拍仍0/51，不能把fixture函数契约测试当UI验收。
- 旧PNG动作ID只可由既有支持脚本对应路线核预期；像素不编码ID，不能据此冒称旧生成回执完整认证。新截图须保留原生capture manifest。
