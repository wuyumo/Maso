# App Store 卖点重做（Plan A）· 2026-11-08

按「先立承诺、再给证据」的原则重排海报，并把演示画面改成「一页一屏」。
本批次只有 **iPhone 6.9″ × 4 种语言（5 页）+ iPad 13″ × 4 种语言（4 页）** 的成品，用于确认卖点与文案；12 语言与其他设备（iPhone Duo / Apple Watch）在确认后才补。

- 工程：`design/app-store-studio-2026-10-29`（`app-store-screenshots.json` 为唯一权威状态）
- 成品：`exported/ios/iphone/1320x2868/<locale>/<NN-slide>.png` 20 张 + `exported/ios/ipad/2064x2752/<locale>/<NN-slide>.png` 16 张，全部 RGB、无 alpha
- 校验记录：`exported/export-validation.json`（逐文件 SHA-256 / 尺寸 / mode）
- 浏览：`cd docs && python3 -m http.server 8840` → `http://127.0.0.1:8840/store-gallery-2026-11-08/`，批次选「11-08 Plan A 预览」（服务根目录必须是 docs/，图片走相对路径 `../store-*`）

## 五页结构

| # | 卖点 | 演示画面 | 中文主文案 | English |
|---|------|----------|-----------|---------|
| 01 | AI 教练（一张照片就有计划） | **无设备 mockup**：画布上直接画聊天气泡（`slide.chat`），一屏之内走完 App 的真实链路——① 发两张身材照（同一模特正面 + 背面）并提要求（3 天 × 45 分钟）→ ② coach 四行身材解读 + 「建议重点」报告（胸/背 mini 肌肉图，附光线与站姿的免责一句）→ ③ 排出来的三天**并排**画成 App 的 `WorkoutCard`（DAY n + AI 徽章、标题、动作数·组数、肌肉图、动作胶囊、卡底「存入训练计划」胶囊）→ ④ 卡下批量「保存到我的训练计划」胶囊。`footnotes` 为空，底部三枚药丸已撤 | 一张照片，就有一周计划 | One photo in, a week planned out |
| 02 | 身体与恢复 | `muscle-selected`（3D 肌肉图 + 肩 49% 恢复中） | 肌肉恢复，一眼看清 | See what has recovered |
| 03 | 心率上限提醒（手机 + 手表） | `player-heart-warning`（播放器 + 越限心率卡 185 bpm / 个人上限 155）＋ `watch/exercise-185`（同一读数、同一动作、同一组） | 心率过高，立刻提醒 | Past your limit? You'll know |
| 04 | 饮食与睡眠 | `diet`（660 宽，**左前方最上层**，−4°，@ 90,1330）+ `sleep`（620 宽，**右后方下一层**，+4°，@ 565,835）——双屏**刻意重叠**而非出血：水平重叠 229pt（睡眠屏机身的 34.5%），睡眠屏被抬高到其标题行与 `7 小时 34 分` 主数字整体位于饮食屏顶边（y 1307）之上，接缝只压到装饰性柱状图、不压任何文字；两台都完整落在画布内（union bbox x[42.3, 1273.9] y[813.4, 2746.2]，余量 左 42.3 / 右 46.1 / 底 121.8） | 饮食与睡眠，一起照顾 | Nutrition and sleep, together |
| 05 | 全设备 | **四设备同框**（`slide.lineup`），按扑克牌方式从左下往右上扇形展开、**头部逐级向右转**：Apple Watch（270 宽，−20°，z4）→ iPhone（380 宽，−6°，z3）→ iPhone Duo（580 宽，+5°，z2）→ iPad（800 宽，+13°，z1）。角度是**严格单调**递增的（−20 → −6 → +5 → +13），宽度也严格单调递增，两条梯度同向，所以读起来是「一叠牌被从右上往左下摁开」而不是四台随手摆放；四台都完整在画布内（union bbox x[50.6, 1279.2] y[803.4, 2701.7]）；四台各放**不同**页面的真实截图（`watch/rest-160`、`iphone/today`、`duo/diet`、`ipad/insights`），避免看起来像同一张图重复；iPad 与 Duo 用 **Apple 官方 Product Bezels**（实拍质感边框 PNG + 透明屏幕孔，`/ipad-frame.png` 1600×2089、`/duo-frame.png` 1600×2233），见「05 四设备 lineup」 | 每一块屏幕，都在一个 App 里 | One app, every Apple screen |

> 03 的副文案（`textElements[description]`）：`超过你设的上限就变红提醒。／心率变化还能自动记组、跳过休息。` / `Turns red past your own limit; heart-rate shifts can also auto-log sets or skip rest (optional, undoable).` —— 主文案只承诺「提醒」，实验性的自动化只出现在副文案里并带「可选／可撤销」限定。**四语言副文案都压成 2 行**：CJK 主文案（137px/行）比拉丁（117px）更高，副文案一旦换成 3 行，`FittedCopy` 会把整块文案缩到 0.92×（03/05 曾如此），与相邻页字号不一致。

相对六页版（同日更早一版）的变化：

1. **03 与 04 合并**：独立的「心率提醒」页被取消，心率改在训练页以播放器心率卡出现。业主判断「专注训练」单独不足以成页，合并后六页变五页。**2026-11-08 追加（本轮）**：心率卡从「160 bpm 正常态」改为「185 bpm 越个人上限 155 的告警态」，主文案从「记录」改为「提醒」，见下方「本轮三处改动（2026-11-08 晚，业主口头指定）」。
2. **手表并入 03**：Apple Watch 不再单独成页，而是摆在训练页手机右侧，且与手机显示同一个读数（现为 185 bpm）、同一个动作、同一组（1/3、8 次、60 kg）。
3. **进步页已撤下**：当日上午曾用「4 周 · 记录组数 + 动作进步 45→55 kg」做 04 页，当前 deck 已没有该页——04 回到「饮食与睡眠」，05 回到「全设备」。`insights-progress` fixture 与 `MASO_MARKETING_PROGRESS` 仍在代码里，恢复时在 `slidesByDevice.iphone` 插回 progress slide 即可。
4. 顺序：计划 → 恢复 → 训练+心率 → 饮食睡眠 → 全设备；首图仍承担最强的搜索意图（「AI 定制计划」），由「一张照片就有一周计划」表达。
5. **删除**「900+ 动作，按器械找」整页；**去掉 193 bpm** 这类极端数值做卖点。
6. **01 改成 AI Coach use-case 页（同日第三版，本轮再改成完整链路 + App 卡片）**：不再放手机 mockup，直接把对话气泡画在画布上。理由：首图是详情页曝光后第一张、也是搜索列表唯一的缩略图，用「一张照片 → 一周计划」这句最强承诺做钩子，然后在一屏里把 App 的真实流程整段演出来——①发两张身材照（同一模特正面 + 背面）+ 提要求（3 天、每次 45 分钟）→ ②coach 四行身材解读（正面上胸偏薄 / 肩臂线条 / 背面中下背平、背阔不足 / 腿围正常先补胸背）+ 「建议重点」报告（胸/背 mini 肌肉图 + 光线站姿免责一句）→ ③排出来的三天**并排**画成 App 的 `WorkoutCard` 本体（`第 1 天 · 胸 + 三头 · 6 个动作 · 19 组` + 胸/三头肌肉图 + 6 个动作胶囊 + 卡底「存入训练计划」胶囊；Day 2 背+二头 5/16、Day 3 腿+核心 5/15）→ ④三张卡下面一枚批量「保存到我的训练计划」玻璃胶囊。三块内容与 App 实体一一对应：`bodyPhotoFocusMuscles`（报告里的重点部位）、`CoachScreen.coach.planCarousel` 的 `WorkoutCard(showsExercisePills:true)`（kicker+`PlanSourceBadge(.ai)` / 标题 / 动作数·组数 / 肌肉图 / `ExercisePill` / 卡底 `AddToPlansButton`）、`isLatest` 那条 `AddToPlansButton(titleOverride: "Save to My Routines")`（= 卡下的批量胶囊，文案取 App 的 `NSLocalizedString("Save to My Routines")`）。报告末尾不放 `Create a plan` 按钮：静态海报里按钮会截断流程，三天卡片已经把「点了之后还有下文」说完，不再靠裁切暗示。落地方式见「构图参数」里的「01 聊天气泡页」「01 气泡页内部尺寸」「01 三列 WorkoutCard」三条；文案与气泡内容都在 `app-store-screenshots.json` 的 `slidesByDevice.iphone[plan].chat`（`rowCards:true` + `ctaAfterCards:true` + 一条 `cta`，`footnotes` 已空）。身材照是两张独立素材 `public/chat/body-front.jpg`、`public/chat/body-back.jpg`（各 480×728），同一张正面 + 背面合成一组——给背面是因为 App 的 prompt 明令「看不见的背/腿不要编」，只放正面却让 coach 讲背面自相矛盾。消息形状照 App 抄：用户那一轮是「照片在上 + accent 12% 气泡（绿字）」，coach 那一轮没有气泡、只有左对齐文本，所以正文/报告/卡片行共用 `x 96` 这一条竖线。

7. **顶部品牌签名去掉（同日第四版；胶囊已在收尾轮删除）**：每页顶部原有一条「设备图标 + MASSO logo」的签名行，占掉正文上方约 115pt 却没有信息价值（App Store 页面本身已给出名称与图标）。第四版先把 logo 删掉、三个设备图标收进右下角的毛玻璃胶囊；**收尾轮把胶囊整枚删掉**（业主：「把右下角的 iPhone、iPad 和 Apple Watch 组件以及它的阴影都去掉」）——`marketing-brand.tsx` 已删除，`slide-canvas.tsx`、`device-showcase.tsx` 的调用点已清，`grep -rn MarketingBrand src/` 无命中，每页右下角只剩背景，见下节「本轮三处改动」第 1 条。同时整体上抬：文案区顶边 225 → 150，02 手机 900 → 815，04 饮食/睡眠 1010/1150 → 940/1080，01 聊天块 800/1955 → 745/1950（后为对齐四语言底部药丸基线收到 745/1880、再因消息重做收到 745/1892，最终因换成三列 `WorkoutCard` 收到 745/**2050**）；03/05 后来重做过构图，坐标见下（03 手机 400/850 +6°、手表 80/1907 −9°；05 四设备 lineup 见下）。（第四版的胶囊实现在 `marketing-brand.tsx` + `slide-canvas.tsx` 的 zIndex 8 包装层，这两处现在都已不存在。）

## 2026-11-09 第四张与第五张重排（本轮，业主口头指定）

只动 Studio 工程（`app-store-screenshots.json`、`device-frames.tsx`、`device-lineup.tsx`、`device-showcase.tsx`、`public/ipad-frame.png`、`public/duo-frame.png`），App 源码未改。

1. **04 改成「重叠但不切」**（业主：「把饮食和睡眠这两个手机用重叠的方式放，睡眠不需要做那么小。两个手机都要完整显示在屏幕中，只是会有一个重叠的区域」）。上一版睡眠屏 620 宽、右缘出血 270pt 到画布外，读起来像被裁坏，而且与 800 宽的饮食屏不成对。现为 diet `660 × 1349.33 @ (90, 1330) / −4° / z3`、sleep `620 × 1267.56 @ (565, 835) / +4° / z2`：水平重叠 229pt（睡眠屏机身的 34.5%），两台完整在画布内（union bbox x[42.3, 1273.9] y[813.4, 2746.2]，余量 左 42.3 / 右 46.1 / 底 121.8）。**接缝位置是这一条的关键**：早先把两台摆成高度齐平（1031 / 1216）时，接缝是一条几乎垂直的边，从 y≈1170 一路往下，正好纵向切过睡眠屏的 `睡眠` 标题和 `7 小时 34 分` 主数字，渲染出来读成「小时 34 分钟」——数字的第一位被吃掉，看起来像 bug 而不像重叠。所以现在把睡眠屏整体抬高 196pt、饮食屏下移 114pt，让睡眠屏的头部整块落在饮食屏顶边（y 1307）之上，接缝降到装饰性柱状图那一带；四语言（含数字更长的 en `7 hr 34 min`）都实测主数字完整。参数理由见「构图参数 → 04 双屏页」。

2. **05 的四台摆成严格单调的扇形**（业主：「这四个设备得有一个渐变过程。现在 iPhone Duo 和 iPad 的位置有点凌乱，把它们做成从左下到右上、头部逐渐向右旋转的纸牌打开式排列」）。病灶是旧 x 序列在 Duo→iPad 之间**回退了 31pt**（430 → 399），而角度只差 10°，两台的先后就读不出来。现在角度 −20 → −6 → +5 → +13、x 115 → 230 → 320 → 372、y 2244 → 1734 → 1380 → 880，四条序列全部严格单调；四台并集 `x[50.6, 1279.2] y[803.4, 2701.7]`，右缘从越界的 1300.3 收回 1279.2，四台全部落在画布内。见「构图参数 → 05 四设备 lineup」。

3. **iPhone Duo 与 iPad 换成 Apple 官方 Product Bezels**（业主：「iPhone Duo 和 iPad 的 mockup 没有用对，请直接在网上找相应的 mockup」）。从 `devimages-cdn.apple.com` 的官方 Product Bezels 资源包取 `iPad Pro (M5) 13" - Space Black - Portrait.png` 与 `iPhone Duo - Night Sky - Inner Open Portrait.png`，裁掉外边距成 1600×2089 / 1600×2233，按实测的透明屏幕孔重算 `IPAD_SCREEN` / `DUO_SCREEN`。上一版自绘的 `make_device_frames.py` 产物作废。

4. **iPad / Duo 海报的构图改成按画布比例**（顺手修的，不是业主要求）：`device-showcase.tsx` 里单屏 `1640 宽 @ top 900`、双屏 `1100 宽 @ −20/990` 都是照 1320 画布调的，在 2064 画布上单屏顶出底边 334px、双屏左右各被切掉一截。改成按 `spec.w / spec.h` 取比例后，`01 / 02 / 04 / 05` 四页在 iPad 上都不再裁切（`03` 不在 iPad 批次里）。双屏的上下位置**按设备分开**：iPad 用 `0.315 / 0.400`，Duo 用 `0.270 / 0.440`——Duo 边框比 iPad 更高（1600×2233 vs 1600×2089），同样的宽度比例会让睡眠屏的内容整体下沉，`7 小时 34 分` 又落到饮食屏后面；抬高后 Duo 与 iPad 一样主数字完整。

5. **文案按画布宽度缩放**（同样顺手）：`FittedCopy` 只在**高度**溢出时缩字号，宽度溢出不会缩、只会折行。Duo 画布 2007 宽比 iPad 的 2064 窄 2.8%，`饮食与睡眠，一起照顾` 在 Duo 上正好差 2px 放不下，折成了「饮食与睡／眠，一起照顾」——`睡眠` 被劈开。现在字号与左右内缩都乘 `cw = spec.w / 2064`，Duo 上 `睡眠` 回到一行。

**验证方式**：这轮补了一个 `src/app/render/page.tsx` 路由（`/render?device=iphone|ipad|duo&slide=<id>&locale=<locale>`，只画一张海报、原生像素、不加侧栏/缩放 UI），再用 headless Chrome `--screenshot` 逐张出图核对。所以本轮的构图是**看着实际像素调出来的**，不是只算坐标——`/tmp/geom.py` 那套旋转 AABB 只用来验边界，最终判断按渲染结果。

导出与校验：iPhone 20 张里 `04 / 05` 共 8 张重出，iPad 16 张里 `01 / 02 / 04 / 05` 共 16 张重出（`01`、`02` 因第 4 条的单屏比例变化而变），合计 **24 张**重新写入 `exported/` 与 `exports/latest/`。之后第 1 条又把 04 的接缝位置改了（睡眠屏抬高、饮食屏下移），所以 **iPhone 4 张 + iPad 4 张 `04-diet.png` 又重出了一遍**，合计本轮 32 张次写入。`export-validation.json` 逐文件 SHA-256 更新（`exportedAt 2026-11-09T15:28+08:00`，36/36 verified、failures 0，改动后重新复核全部 36 张的尺寸/mode/hash 一致）。

## 2026-11-09 凌晨三处改动（上一轮，业主口头指定）

只动 Studio 工程（`coach-chat.tsx`、`deck_devices_page.py`、`diet_pair.py`、项目 JSON、素材），App 源码未改。

1. **01 最下面三张训练卡改成 App 的 `WorkoutCard`，按钮也用 App 的按钮**（业主：「最下面那三个训练卡片，用 App 里生成的训练卡片样式，按钮也同样用 App 里生成的样式」）。原来的实现是一条 1020 宽、横向滚动的 carousel，只有第一天完整、第二天被画布右缘裁一半，卡片本身是「放大版」的近似体。现在改成**三张并排**的 App 卡片：kicker 行（杠铃图标 + `DAY n` + 行尾 `AI` 徽章）、标题行（含 chevron）、动作数·组数、肌肉图、`ExercisePill` 胶囊行、卡底 `AddToPlansButton` 形状的「存入训练计划」胶囊；卡片行下面再放一枚批量胶囊（= App `isLatest` 那条 `AddToPlansButton(titleOverride:"Save to My Routines")`，文案取 App 的四语言字符串）。落地参数见「构图参数 → 01 三列 WorkoutCard」。配套代码改动只有 `coach-chat.tsx` 的 `GridPlanCard` / `SaveCapsule` / `SavePill` 三个组件；`chat.height` 因多出一枚胶囊与两行标题的余量从 1892 收到 **2050**。
2. **04 饮食屏改到左前、最上层，睡眠屏退到右后、下一层**（业主：「饮食屏幕靠左、放在左前方最上层；睡眠屏幕放在右边、下面那一层」）。此前恰好是反的（睡眠 820 宽 +3° 在前、饮食 760 宽 −3° 在后）。现在是 diet `800 × 1635.56 @ (60, 1010) / −3° / z3`、sleep `620 × 1267.56 @ (938, 1165) / +3° / z2`，睡眠屏右缘刻意出血到画布外。两者关系写在 `scripts/diet_pair.py` 的注释里，见「构图参数 → 04 双屏页」。
3. **05 四设备按真实物理比例重排，把 iPad 放大**（业主：「Apple Watch 和前面的 iPhone 可能要缩小一点……现在感觉显得 iPad 有点太小了」）。旧的 310 / 450 / 520 / 590 让 iPad 只有 787 高、比 920 高的 iPhone 还矮，所以「最大的一台」读成了最小剪影。新值 watch 235 / iPhone 345 / Duo 540 / iPad 780（≈ 0.7× / 1× / 1.55× / 2.3× 的真实物理宽度，高度由各自边框比例反推），iPad 变成 1040 高 × 780 宽、旋转后 bbox 1022.6 × 1206.4，终于既是最高也是最宽的一台。落地在 `deck_devices_page.py` 的 `LAYOUTS["fan"]`，见「构图参数 → 05 四设备 lineup」。

导出与校验：`/tmp/studio-out/final-dev5`（iPhone 四语言 20 张），02 / 03 与上一批逐字节相同，01 / 04 / 05 全部变化；`export-validation.json` 重新生成（`exportedAt 2026-11-09T02:10+08:00`，36/36 verified），画廊批次 `v=20261109c`，selftest ALL PASS (31 checks)。

## 本轮三处改动（2026-11-08 收尾，业主口头指定）

只动 Studio 工程（`marketing-brand.tsx`、`device-frames.tsx`、`device-lineup.tsx`、`slide-canvas.tsx`、`device-showcase.tsx`、`make_device_frames.py`、项目 JSON），App 源码未改。

1. **右下角设备胶囊整块删除**（业主：「所有图片右下角多设备的图像都去掉吧：把右下角的 iPhone、iPad 和 Apple Watch 组件以及它的阴影都去掉」）。上一版每页右下角那枚毛玻璃胶囊（三个 `lucide` 设备图标 + `0 18px 46px rgba(0,0,0,.45)` 投影 + `inset: -58` 径向羽化遮罩）连同它压暗背景的那层阴影一起删掉：`src/components/editor/marketing-brand.tsx` 整个文件删除，`slide-canvas.tsx` 里那个 `zIndex 8` 的包装层与 `import` 一起删，`device-showcase.tsx`（iPad／Duo 海报）的调用也删；顺带删掉仍引用它的过期备份 `device-showcase.tsx.before-device-down-20261108`，所以 `grep -rn "MarketingBrand\|marketing-brand" src/ app-store-screenshots.json` 现在无命中。删掉的只有右上角那枚图标——文字、设备、出血位置一个像素都没动（同一份 deck 重导出的 01–04 与上一批逐字节相同，只是不再画胶囊）。
2. **05 扇形的顺序改成 Apple Watch → iPhone → iPhone Duo → iPad**（业主：「把 iPhone 放在第二个，然后把 iPhone Duo 放在第三个，最后是 iPad」）。扇形是「尺寸随对角线递增、倾角逐级朝右」的几何，所以这次不是换 z 序，而是把 `LAYOUTS["fan"]` 里 iPhone 与 Duo 两个 slot 的**整组参数**互换：iPhone 拿到前排的 (200, 1800) / 450 宽 / −6° / z3，Duo 拿到中排的 (380, 1240) / 520 宽 / +5° / z2。逐字节复核过旧参数就是现在 Duo 的那组，所以四台的实际尺寸、角度、遮挡关系没有副作用，只有「第二台是谁」变了。改的是 `deck_devices_page.py` 的 `LAYOUTS["fan"]` 并重跑脚本（**不要**手改 JSON，下次跑脚本会被覆盖）。
3. **iPad 与 iPhone Duo 改用实拍质感边框 PNG**（业主：「iPhone Duo 跟 iPad，找一个 mockup（类似 iPhone 跟 Apple Watch 这样子的）把截图做在 mockup 上，不再用 CSS 画机身」）。机器上确实没有可用的 iPad / Duo 实拍边框：`/Library/Developer/CoreSimulator/Profiles/DeviceTypes/` 里只有 1C896A2B 的 framebuffer mask PDF 与 sensor bar PDF（几十 KB 的矢量遮罩，不是设备照），`iPhone Duo.simdevicetype`（V68 / iPhone19,4 / chromeIdentifier `com.apple.dt.devicekit.chrome.phone15`）也只描述参数、不含边框美术；网上素材站要么要账号要么授权不明。于是改成**本地生成**：`docs/store-plan-a-2026-11-08/scripts/make_device_frames.py` 用 numpy + PIL 生成两张 RGBA 叠层（`public/ipad-frame.png` 1500×2000、`public/duo-frame.png` 1400×1990），照着 `/mockup.png` 量出来的解剖结构画——深色铝质肩线 → 一道 1.1px 亮边 → 黑玻璃边框 → 完全透明的屏幕孔，再叠斜向渐变反光、玻璃暗角、镜面高光条纹、拉丝噪点、侧键、顶部居中的摄像头；Duo 另外在屏幕孔里烤进一条 5.2% 宽的中缝（含一条低透明度高光）。渲染层换成 `device-frames.tsx` 里新写的共享 `BezelFrame`：屏幕 `<img>` 铺在透明孔里（`IPAD_SCREEN` / `DUO_SCREEN` 百分比裁切 + 圆角），边框 PNG 用 `position:absolute; inset:0; zIndex:2` 盖在上面，外部投影由同一个 `filter: drop-shadow(...)` 给——与 Phone／Watch 完全同一套模式，之前那堆 CSS 金属渐变、`inset` 内阴影、iPad 摄像头圆点、Duo 的中缝 `div` 全部删除。两张边框 PNG 也加进 `screenshot-editor.tsx` 的预热列表，避免首帧闪空。

## 上一轮四处改动（2026-11-08 深夜，业主口头指定）

只动 Studio 工程（`coach-chat.tsx` + 项目 JSON + 素材），App 源码未改。

1. **身材分析文案写满四行**（业主：「肌肉分析文案有点太少」）。依据是 App 自己的 `AIWorkoutService.analyzeBodyPhoto` prompt——`summary` 要覆盖「可见的相对发达程度 / 建议加强的部位 / 照片本身的局限」三段，所以 zh 从两行扩到四行：正面胸肌中下束厚、上束偏薄 → 肩前束与手臂线条 → 背面中下背平、背阔肌外展不足 → 腿围正常、先补胸背；`report.note` 改成「光线和站姿会影响判断，只作训练重点参考。」对应 prompt 里的 photo limitations。四语言同构，均为 4 行、无 `FittedCopy` 缩放。
2. **demo 照换成同一模特的正面 + 背面**。素材是 `public/screenshots/apple/iphone/coach-body-front-back.png`（1536×1024，正背并排），裁 `(180, 0, 1340, 660)` 取到「头 → 短裤下缘」的两个人，放大到 1280×728（1.758）存成 `public/chat/body-front-back.jpg`。（**已被 2026-11-09 凌晨那一轮取代**：改成两张独立素材 `body-front.jpg` / `body-back.jpg`，各 480×728、按 App 的 `CoachUserPhotoGrid` 5:6 并排；`body-front-back.jpg` 留在 `public/chat/` 未删，但已无引用。）理由：App 的 prompt 明确要求「没看见的背/腿不要编」，只给正面照却让 coach 讲背面是自相矛盾的；给了背面报告才站得住。照片从 280×280 方形（`objectFit: cover`，会把两个人各切掉一半）换成按素材比例的横向块，宽度由竖向预算反推。
3. **消息形状改成 App 的形状**（业主：「消息的样式参考一下 App」）。对应 `CoachScreen`：用户那一轮是右对齐 `VStack(alignment:.trailing, spacing:4)`——照片在上、`CoachUserTextBubble` 在下，气泡底色 `MasoColor.accent.opacity(0.12)`、文字用 accent 色；coach 那一轮**没有气泡**，只有左对齐的文本 + 附件。于是 coach 侧的 `rgba(255,255,255,.045)` 底、描边、投影、36 圆角全部删掉，只留 `AI 教练` eyebrow 交代说话人。
4. **对齐与间距**（业主的①②）。删掉 coach 气泡后，正文、报告块、计划卡三者的左缘全部落在 `x 96`（`data-chat-message[data-chat-message="assistant"]` / `data-chat-report` / `data-chat-plan-track` 的 `x` 都是 96）——之前 coach 气泡的边框在 96、内部内容在 130，而计划卡在 130，读者看到的是「气泡边 vs 卡片边」的错位。间距从 `justify-content: space-between`（把 380pt 余量平均分给三处，实测 130 / 126）改成固定值：照片 → 用户气泡 16、用户气泡 → coach 回复 46、coach 回复 → 计划卡 **26**、计划卡 → 底部药丸 **34**。（**16 / 46 / 26 / 34 已被 2026-11-09 凌晨那一轮取代**：现在的常数是 `photoGap 16` / `gapTurns 56` / `gapReply 34` / `gapPills 40`，即「换人说话」最松、回复与卡片行、卡片行与批量胶囊收紧。）

## 上一轮三处改动（2026-11-08 晚，业主口头指定）

三处都只在 Studio 工程与素材层完成，App 源码未改。

1. **01 去掉 CTA、改成横向计划卡**（覆盖同日更早的「报告 + `Create a plan` 按钮」；**这一版的横向轨道已被 2026-11-09 凌晨的三列 `WorkoutCard` 取代**，见上方那节）：报告气泡下面直接接排出来的日程卡，第一张完整、第二张被画布右缘裁开。理由：静态海报里的按钮只会截断流程，而「露出一角的下一张卡」本身就把「还有更多天」说清楚了。数据层是 `ChatBubble.plans`（`types.ts` 新增，保留单张 `plan` 兼容旧数据），渲染层是 `coach-chat.tsx` 的 `PlanCard` + 气泡外的 `data-chat-plan-track` 兄弟轨道。
2. **05 改成扑克牌扇形**（覆盖同日「两排对齐」版）：最小的一台放最左下且最前，其余依次向右上错开并逐级加大旋转角，见下方 slots 表。同时把 iPad 的 CSS 机身做成照片质感（业主指出「iPad 和 iPhone 都要做成 mockup」——iPhone 本来就是实拍叠层，iPad 只有 CSS 机身）。

   > 两版都留在 `deck_devices_page.py` 里：`LAYOUTS["fan"]`（扇形，默认、即当前成品）与 `LAYOUTS["grid"]`（两排 2×2 对齐，四个屏幕全正面、倾角 ≤2°）。切换只要 `python3 docs/store-plan-a-2026-11-08/scripts/deck_devices_page.py grid`，再导出一次；**不要**手改 JSON 的 slot 数字，否则下一个人重跑脚本就会被覆盖回去。取舍：扇形更有张力、更像产品照，代价是四台互相压边（Duo 只露出饮食屏左半、iPad 被手机压住左下角）；两排最清楚、最好读，但气质偏图鉴。两排版的成品留在 `/tmp/studio-out/final-dev4`（iPhone，四语言）备选。
3. **03 改用同一套语法**（覆盖同日「手机在前居中、手表右下」版）：手表 500 宽摆左下、`−9°`（头部向左靠）、`zIndex 3` 在最前；手机 820 宽退到右后、`+6°`（头部向右靠）、`zIndex 2`。

## 构图参数

画布 1320 × 2868（`CANVAS.iphone`）。

- 文案区：`caption` (112, **150**, 1096, 545)；描述块与主文案同一容器。顶部不再有品牌／设备签名行，所以正文直接贴到 150
- 单屏机位（02）：`device` 1080 × 2208 @ (120, **815**)，无旋转，底部出血约 155pt（当年是为右下角胶囊让位收的，胶囊已删除，出血量沿用这一版——重排就要重挑屏幕内容与裁切位置，收益抵不上风险），手机仍被下边裁切、不露出完整下框
- **01 聊天气泡页**：`slide.chat` 存在时 `slide-canvas.tsx` 不再渲染任何设备边框，改为 `<CoachChat>`（zIndex 6）。坐标写在 `chat` 里、以 1320 宽参考画布计（`x 96 / y 745 / width 1128 / height 2050`），组件用 `k = cW / 1320` 缩放，所以换画布尺寸不用改数字。根容器是 `justify-content: flex-start` + 每块自带 `marginTop`（**不是** `space-between`：余量绝不能均摊，否则 coach 回复会从它的卡片行旁边飘走）。四语言实测（`probe21.mjs`，1320 参考）：照片组 `x 626 / y 745 / 598×355`（两张各 `292×355`、间距 14，右缘 1224 与气泡右缘齐）→ 用户气泡 `x 720 / y 1116 / 504×186.8`（zh、zh-Hant、ja；en 因文案长是 `660.3` 宽、右缘仍贴 1224）→ coach 消息 `y 1358.8 / 高 497.1`（4 行文本 + 报块 320）→ 卡片行 `x 96 / y 1889.9 / 1128×654.6`（zh、zh-Hant）或 `1128×742.6`（en、ja）→ 批量保存胶囊 `y 2584.6`（zh）/ `y 2672.6`（en、ja），可见底边 2679.6 / 2767.6，画布 2868 留 100–188 余量。竖向节奏固定为：照片底 1100 → 气泡顶 1116（16）、气泡底 1302.8 → coach 1358.8（56 = `gapTurns`）、coach 底 1855.9 → 卡片行 1889.9（34 = `gapReply`）、卡片行底 → 批量胶囊顶 40（= `gapPills`）。文本块底边 zh 679.8 / ja 661.9，与聊天块之间留 65–83。气泡文字支持 `\n` 写死换行（`whiteSpace: pre-line`），RTL 用 `dir` 切换、卡片行向左侧出画（`alignSelf: stretch` 到根宽 1128）。
- **03 双设备（放大并倾斜）**：手机 `device` 820 × 1676.4 @ (**400, 850**)，**+6°**（「头部向右靠」），zIndex 2；手表 `deviceSecondary` 500 × 785.71 @ (**80, 1907**)，**−9°**（「头部向左靠」），zIndex 3——和 05 页同一套「扑克牌」语法：手表这台最小的摆在左下、在最前方，手机退到右后侧，两台各自朝展开方向倾斜制造纵深。手机底部出血是刻意构图，手表整只（表壳、表带）在画布内且不遮心率卡与组/次/重量。`slide-canvas.tsx` 里 `isWatchScreen()` 按元素自身图片路径判定是否用 Watch 边框，因此一页可以同时有手机边框和手表边框。
- **04 双屏页**：**饮食屏在最前、靠左**（`device` 660 × 1349.33 @ (**90, 1330**)，−4°，zIndex 3），**睡眠屏在右后、下一层**（`deviceSecondary` 620 × 1267.56 @ (**565, 835**)，+4°，zIndex 2）。业主的口头要求是「把饮食和睡眠这两个手机用重叠的方式放，睡眠不需要做那么小。两个手机都要完整显示在屏幕中，只是会有一个重叠的区域」，所以这一页的约束是三条同时成立：**必须重叠**、**两台都不能出画布**、**睡眠屏不能被做小**。1320 的画布装不下两台各自 660+ 宽的机器（660×2 + 双边框 88 = 1408 > 1320），因此重叠在几何上是强制的，问题只剩「接缝落在哪」。第一版把两台摆成高度几乎齐平（睡眠 1031 / 饮食 1216），接缝接近一条垂直线、从 y≈1170 一路贯到 2400，纵向切穿睡眠屏的 `睡眠` 标题与 `7 小时 34 分`——渲染出来读成「小时 34 分钟」，主数字的第一位被吃掉，看起来像渲染 bug。现版把**睡眠屏抬到 835、饮食屏降到 1330**（差 495pt），睡眠屏的头部整块位于饮食屏顶边（旋转后 bbox 顶 y 1307）之上，接缝于是落到 `7 小时 34 分` 之下、只压在装饰性柱状图上。实测旋转 bbox：睡眠屏 753.9 × 1354.7（x 520.1–1273.9、y 813.4–2168.1），饮食屏 799.5 × 1439.1（x 42.3–841.7、y 1307.1–2746.2）；union `x[42.3, 1273.9] y[813.4, 2746.2]`，余量 左 42.3 / 右 46.1 / 底 121.8，两台完整在画布内。机身水平重叠 `794 − 565 = 229pt`，占睡眠屏机身的 34.5%。`±4°` 让重叠区的两条机身边明显分开，读得出「两台前后叠着」而不是「一台被切成两半」。**边界同样很窄**：饮食屏再左移会顶出画布左边（bbox 左缘只剩 42.3），睡眠屏再右移会把右缘推过 1280，睡眠屏再下移则接缝立刻回到主数字上。高度一律由 `width × (2868/1320 − 边框修正)` 反推，即 `width × 2.0444`。换序真正生效的位置是 `src/lib/marketing-localized.ts` 的 `scenes.diet = ['diet','sleep']`——只改 JSON 的 `screenshot` 字段不会换图。
- **05 四设备 lineup**（`slide.lineup.slots`，1320 参考宽，`zIndex` 越大越靠前）：不再分两排，改成**一副扑克牌从左下往右上扇形展开**——最小的一台在最左下且最靠前，越往右上尺寸越大、角度越朝右倾、越靠后：

  | slot | 尺寸 / 位置 | 角度 | z | 截图 |
  |---|---|---|---|---|
  | `watch` | 270 @ (115, 2244) | −20° | 4 | `watch/rest-160` |
  | `iphone` | 380 @ (230, 1734) | −6° | 3 | `iphone/today` |
  | `duo` | 580 @ (320, 1380) | +5° | 2 | `duo/diet` |
  | `ipad` | 800 @ (372, 880) | +13° | 1 | `ipad/insights` |

  本轮重排的动机是业主嫌「iPhone Duo 和 iPad 的位置有点凌乱」（2026-11-09：「这四个设备得有一个渐变过程。现在 iPhone Duo 和 iPad 的位置有点凌乱，把它们做成从左下到右上、头部逐渐向右旋转的纸牌打开式排列」）。上一版的病灶是角度序列 −16 → −6 → +5 → +15 配 x 序列 57 → 157 → 430 → 399：**x 在 Duo 与 iPad 之间回退了 31pt**，而角度差只有 10°，于是 Duo 与 iPad 挤在一起、读不出先后。现值把两条序列都做成严格单调：角度 −20 → −6 → +5 → +13（级差 14 / 11 / 8，越往上越收敛，像真的一叠牌被捏住根部甩开），x 115 → 230 → 320 → 372、y 2244 → 1734 → 1380 → 880（每级都在右上方向前进，没有回退）。宽度 270 / 380 / 580 / 800 仍按各机真实物理比例给（13″ iPad ≈ 2.3× iPhone、Duo 内屏 ≈ 1.55×、Watch 表壳 ≈ 0.7× 为可读性放大），高度由 `device-lineup.tsx` 的 `ASPECT` 各自反推（Watch 270→424.3、iPhone 380→776.9、Duo 580→809.5、iPad 800→1044.5）。实测旋转 bbox：

  | slot | bbox 宽 × 高 | 左 / 右 | 上 / 下 |
  |---|---|---|---|
  | `watch` | 398.8 × 491.0 | 50.6 / 449.4 | 2210.6 / 2701.7 |
  | `iphone` | 459.1 × 812.4 | 190.4 / 649.6 | 1716.3 / 2528.6 |
  | `duo` | 648.3 × 856.9 | 285.8 / 934.2 | 1356.3 / 2213.2 |
  | `ipad` | 1014.5 × 1197.7 | 264.8 / 1279.2 | 803.4 / 2001.1 |

  四台并集 `x[50.6, 1279.2] y[803.4, 2701.7]`，余量 **左 50.6 / 右 40.8 / 底 166.3**，顶边 803.4 比副文案底边 745 低 58.4 —— 四台全部在画布内，不再依赖 `overflow:hidden` 裁切（上一版 iPad 右缘 1300.3 已经越界）。`zIndex` 4→1 保证前面的小设备不被后面的大家伙盖住，同时每台都至少露出一块能认出的屏幕：watch 整只在画布内，iPhone 露出完整今日页的标题与训练卡，duo 露出饮食屏右半与`700 / 2,140 kcal`主数字，iPad 露出「训练洞察」的肌群条与力量进度。实现在 `device-lineup.tsx`（只读 JSON slots，不改代码），iPhone 1320 画布上是 1:1 绘制（`scale = cW/1320`），**不走** `fitLineup()`——`fitLineup()` 只服务 iPad / Duo / Watch 海报（`device-showcase.tsx` 的 `{90, 800, spec.w−180, spec.h−910}` 盒），所以量位置必须用旋转后的 bbox，而不是 style 的 width/height。
- **iPad / Duo 边框是 Apple 官方 Product Bezels 叠层**（2026-11-09 本轮换掉本地生成的近似体）：`device-frames.tsx` 的 `IPad` / `Duo` 与 `Phone` / `Watch` 同一套做法——共享组件 `BezelFrame` 先把截图 `<img>` 铺进透明屏幕孔（`IPAD_SCREEN` = L4.002 / T3.202 / W91.774 / H93.733、圆角 4.3% × 3.225%，`DUO_SCREEN` = L3.273 / T2.345 / W93.829 / H95.578、圆角 4.8% × 3.377%），再把 `public/ipad-frame.png` 或 `public/duo-frame.png` 以 `inset:0 / zIndex:2` 盖在上面，落地阴影统一用 `filter: drop-shadow(0 26px 34px rgba(0,0,0,.5)) drop-shadow(0 4px 10px rgba(0,0,0,.35))`。两张 PNG 直接取自 Apple 官方设计资源包（`devimages-cdn.apple.com` 的 Product Bezels DMG，`iPad Pro (M5) 13" - Space Black - Portrait.png` 与 `iPhone Duo - Night Sky - Inner Open Portrait.png`，裁掉外边距后为 **1600×2089** 与 **1600×2233**），屏幕上就是真的实拍机身：铝质肩线、天线带、侧键、镜头开孔、玻璃反光全在，屏幕孔是真透明。上一版的 `scripts/make_device_frames.py`（numpy + PIL 自绘的近似边框，1500×2000 / 1400×1990）已被取代——业主当时的原话是「iPhone Duo 和 iPad 的 mockup 没有用对，请直接在网上找相应的 mockup」，自绘版无论怎么调参都不像实拍。**屏幕孔百分比必须与 PNG 实测一致**（`IPAD_SCREEN` / `DUO_SCREEN` 现在是量出来的，不是估的），否则截图会从孔里露到边框上，或孔里露出黑边。`device-lineup.tsx` 的 `ASPECT.ipad` / `ASPECT.duo` 用的是**机身**比例（1600/2089、1600/2233），不是屏幕孔比例，高度才对得上。
- 四台放**四种不同画面**（`lineupScenes` 在 `src/lib/marketing-localized.ts`）：iPad 用 `insights`（大屏能一屏放下肌群条 + 力量进度 + 训练历史，最能体现平板价值）、Duo 用 `diet`、iPhone 用 `today`、Watch 用 `rest-160`；早前 iPad 与 Duo 都放 `insights` 时四张图看起来重复。Duo 的中缝现在烤在 `duo-frame.png` 里（`make_device_frames.py` 的 `crease: 0.052`，5.2% 宽 + 一条低透明度高光），不再由 `device-frames.tsx` 用两层 `div` 叠——摆在一台 iPad 旁边时它是「折叠屏」而不是「小号平板」的唯一线索，别删。iPad / Duo 展示图（`DeviceShowcase`）走 `fitLineup()` 把同一份 slots 等比居中缩进海报下半区，所以补做这两台设备时不用重排版。
- **01 气泡页内部尺寸**（`coach-chat.tsx`，全部按 `k = cW/1320` 缩放）：正文 52、eyebrow 24、chip 40、批量保存 CTA 44、脚注 36（当前 `footnotes` 为空，不渲染）；报告块肌肉图槽 320、label 32 / name 40 / note 32；照片用 App 的 `CoachUserPhotoGrid` 形状——两张各 `292×355`（5:6 竖幅）、间距 14、圆角 24、`1.5px` 白 12% 描边，整组右对齐、右缘与气泡齐平；用户气泡圆角 52、内距 44×30、底色 `rgba(accent, .12)`、文字 accent 色（= App 的 `CoachUserTextBubble`）；coach 消息无底色、无描边、无投影（= App 的 `assistantMessage`）。
- **01 三列 WorkoutCard**（`GridPlanCard`，App `WorkoutCard(showsExercisePills:)` 的并排版）：三天不再做成可横向滚动的 carousel，而是三等分**并排**（`data-chat-plan-grid`，`alignSelf: stretch` 到根宽 1128、`gap 22`，每张 `flex: 1 1 0` → 宽 361.3；`x 96 / 479.3 / 862.7`）。理由：静态海报里并列三张比「第二张被裁一半」更直白地说明「这就是排出来的一周」，也顺势把每张卡都换成 App 的卡片本体而不是缩小版示意。卡内参数（`k` 缩放）：`padding 26`、圆角 30、底 `rgba(255,255,255,.06)` + `1.2px` 白 10% 描边 + `blur(16)` + 内侧 1px 高光；kicker 行 = 杠铃图标 22 + `DAY n` 24/800/`tracking 2.4/24`/大写 + 行尾 `PlanSourceBadge(.ai)`（sparkles + `AI`，accent 18% 底 / 45% 描边）；标题 42/700/`lineHeight 1.16` + 右侧 22 的 chevron；动作数·组数 26/400/`#B3B3B3`/`tabular-nums`；肌肉图槽 175（`MuscleMap` 的 stroke 0.5）；动作胶囊 = part 18/600 accent + name 20/600 白 90%，`padding 7×12`、`borderRadius 999`、底 `#262626`（= App 的 `MasoColor.surfaceHi`）、间距 7，最多 6 枚（App 的 `LimitedFlowLayout` 本来就全画，6 只是留给未来更长计划的保险，超出才出现 `+N`）；卡底 `marginTop: auto` + `paddingTop 14` 钉住「存入训练计划」胶囊（20/600 白 + 20 的 plus 图标、`padding 10×12`、`#262626` 底、`999` 圆角、1px 白 10% 描边，= App 的 `AddToPlansButton`，文案取 `SAVE_LABEL`：en `Save to workout plans` / zh `存入训练计划` / zh-Hant `存入訓練計畫` / ja `トレーニングプランに保存`）。
  - **标题块固定占两行**：`minHeight: 2 × 42 × 1.16`。英文 `Chest + Triceps` 在 361 宽度下会折成两行，而 CJK 标题不折——不预留的话那一张的肌肉图会被压低 48.7pt，三张卡的地标（肌肉图带、胶囊带）就对不齐。修后四语言三张卡的肌肉图都在同一 y（en 实测 card 高 742.6、map y 2103.6、pills y 2290.6、save y 2561.6），overflow 计数全 0。
  - **卡高为什么分两档**：zh / zh-Hant 654.6，en / ja 742.6。差异全部来自动作胶囊的换行行数（en 的 `Close-Grip Bench`、ja 的 `ローププッシュダウン` 更长），不是字号让步——App 的 10/11pt 比例必须保住，所以只靠 361.3 的卡宽与 22 的间距消化。
  - **批量保存胶囊**（`data-chat-cta`，`ctaAfterCards`）：38/700 白、`rgba(255,255,255,.10)` 底、1.5px 白 18% 描边、`blur(16)`、`padding 18×34`、`999` 圆角，左对齐在卡片行下方 `gapPills = 40` 处（zh `x 96 / y 2584.6 / 456×95`，en `584.7×95 / y 2672.6`）；文案直接取 App `NSLocalizedString("Save to My Routines")` 的四种语言值（zh `保存到我的训练计划` / zh-Hant `儲存到我的訓練計畫` / en `Save to My Workout Plans` / ja `マイプランに保存`）。
  - 卡片行是 coach 消息的**兄弟节点**（不计入消息宽度），所以三张卡可以齐根宽 1128；`rowCards` 字段现在还留在 JSON 里但已无渲染作用（只有 `ctaAfterCards` 生效），清不清都不影响成品。
- **右下角不再有设备胶囊**（收尾轮删除）：`marketing-brand.tsx` 整个文件已删（三个 `lucide` 设备图标 44／46／44、间距 16、`padding 12×22`、`border-radius 999`、`backdrop-filter: blur(22px)`、`0 18px 46px rgba(0,0,0,.45)` 投影、`inset: -58` 径向羽化遮罩全部作废），`slide-canvas.tsx` 的 `zIndex 8` 包装层与 `device-showcase.tsx` 的调用一并删除。现在每页右下角只有背景 #212121，没有图标、也没用那层压暗阴影。**不要**把它加回来——业主明确要求去掉。
- 字号（`slide-canvas.tsx`）：CJK 0.104 × 短边、拉丁 0.089、副文案 0.043；行高 zh 1.25 / 其他 1.12
- iPad / Duo 展示页（`device-showcase.tsx`）本轮改成**按画布比例**，不再写死 1320 时代的像素值：文案字号 `headSize = round((CJK?182:138) × cw)`、副文案 `round(62 × cw)`、左右内缩 `round(140 × cw)`，其中 `cw = spec.w / 2064`（iPad 上恰好为 1，Duo 2007 宽上为 0.972）。设备框：单屏 `width = min(spec.w × 0.66, (spec.h × 0.94 − 830) / aspect)` @ top **830**（左右居中）；双屏 `diet 0.52·w @ (0.055·w, 0.40·h) −4° z3` + `sleep 0.49·w @ (0.44·w, 0.315·h) +4° z2`，`aspect = duo ? 2853/2007 : 2752/2064`。**旧的 1100 宽双屏 / 1640 宽单屏是照 1320 画布调的**：在 2064 画布上双屏左右各被切掉一截（左 −20、右 2090 > 2064），单屏 1640 宽换算出 2186 高、top 900 直接顶出 2752 底边 334px——两处都是本轮修掉的。注意工程里没有全局 `box-sizing: border-box`，那圈 `22px solid #171717` 边框是加在 `width` **之外**的，所以上面这些分数都留了 44px 的余量。

## 素材来源与重拍

两张新截图来自原生模拟器 fixture（DEBUG 启动模式，合成数据，不联网、不购买）：

```bash
python3 scripts/low_memory_build.py build
python3 scripts/low_memory_build.py run -- bash docs/store-plan-a-2026-11-08/capture.sh
python3 scripts/low_memory_build.py run -- bash docs/store-plan-a-2026-11-08/capture-watch-rest.sh
```

- `player-heart-warning`：`MASO_EXERCISE_UI_TEST_SCENE=stable-player` + `MASO_WORKOUT_HEART_FIXTURE=1` + `MASO_TEST_HEART_BPM=185` + `MASO_TEST_HEART_LIMIT=155` + `MASO_MARKETING_EXERCISE_ID=bench_press_machine` + `MASO_WORKOUT_HEART_CARD=1`（展开成卡片而不是胶囊）——185 越过 155 的个人上限，画面是真的越限态（心率卡变红 + 整屏偏红底），不是画的示意图
- `exercise-185`：`MASSO_WATCH_PREVIEW=exercise` + `MASSO_WATCH_MARKETING_HEART=1` + `MASSO_WATCH_MARKETING_BPM=185` + `MASSO_WATCH_MARKETING_EXERCISE=bench_press_machine` + `..._REPS=8` + `..._WEIGHT=60` + `..._SET=1`（后五个为新增）——手表与手机同一动作、同一组（1/3）、同样 8 次 60 kg、同一读数 185，03 页讲的是「同一个瞬间」，不是两台各自演示
- `rest-160`：`MASSO_WATCH_PREVIEW=rest` + `MASSO_WATCH_MARKETING_HEART=1` + `MASSO_WATCH_MARKETING_BPM=160`（新增，此前硬编码 128），05 页手表用这一张
- `insights-progress`：`MASO_SHOWCASE=insights` + `MASO_MARKETING_PROGRESS=1`（新增：按「今天往前推」铺满四周的合成训练记录）+ `MASO_MARKETING_INSIGHTS_RANGE=fourWeeks`（新增，仅截图模式可用的初始区间）

iPad 与 iPhone Duo 的边框 PNG 是本地生成的，不是下载的（机器上没有可用的实拍边框，见「本轮三处改动」第 3 条）：

```bash
cd design/app-store-studio-2026-10-29
python3 ../../docs/store-plan-a-2026-11-08/scripts/make_device_frames.py
# → public/ipad-frame.png 1500x2000、public/duo-frame.png 1400x1990（RGBA，屏幕孔全透明）
# 脚本会打印屏幕孔百分比，必须与 device-frames.tsx 的 IPAD_SCREEN / DUO_SCREEN 一致
```

slide → scene 映射：`src/lib/marketing-localized.ts`；导出前素材校验：`src/app/api/capture-readiness/route.ts`。

05 页**没有新拍素材**：四台设备直接复用已导出的本地化截图（`public/screenshots/localized/<family>/<locale>/<scene>.png`），映射表在 `marketing-localized.ts` 的 `lineupScenes`（`iphone→today`、`ipad→insights`、`duo→diet`、`watch→rest-160`），改 `app-store-screenshots.json` 里的 slot 字段不会换图。海报（iPad / Duo）的副文案用 `whiteSpace: pre-line` 渲染，否则 `\n` 会被忽略、自动折行会在宽画布上留下孤零零的一行（iPad 上曾出现「开练。」单独成行）。

01 的聊天气泡目前只写在 `slidesByDevice.iphone[plan]` 上；iPad / Duo / Watch 分类下的 plan 仍是带手机边框的 `plans` 截图。补做这些设备时，要么把同一份 `chat` 抄过去（坐标按 1320 参考宽同样有效），要么明确让 01 保持设备页——不要出现「iPhone 是气泡、iPad 是机身」但文档还写「无 mockup」的不一致说明。

## 文案与诚实性边界

可以说的：无账号、数据在本机、12 种语言、917 个动作、3D 肌肉恢复、AI 周计划、组/次/重量记录、饮食与睡眠记录、Apple Watch 记录。

不能说的（本批次没有说）：

- ❌「每个动作都有视频示范」——`exercises.json` 里 902 条是外链教学视频，不是内置演示
- ❌ 心率不能说成 iPhone 独立能力：数据来自 Apple Watch，03 副文案写明 `Apple Watch`
- ❌ 不写「多设备自动同步」：Masso 目前**没有** CloudKit / iCloud Drive 多设备同步（`PersistenceController.swift` 只有 Documents + iCloud Backup，多设备 ubiquity container 是未落地的 `TODO[deploy-cloudkit-sync]`；`WatchSyncManager` 只是 iPhone↔Watch 的 `WCSession` 桥）。所以 05 页只承诺「都支持」，早期草稿里的「训练记录自动同步 / synced everywhere」已删掉
- ⚠️ 05 副文案必须压成 **2 行**：`textElements[description]` 的容器只有 140pt 高，四语言都由手工 `\n` 断在「设备名 / 都支持…」之间（`iPhone、iPad、iPhone Duo、⏎Apple Watch 都支持，随时开练。`），第三行会溢出
- ❌ 不写「警报／警告」：画面里是 185 bpm 越个人上限（155）时的红色心率卡与整屏偏红底色，文案说的是「提醒」，不是医疗或安全告警，也不承诺干预效果
- ⚠️ 进步页展示的是合成记录（与其它海报的演示数据同性质），不代表真实用户成绩

## 验证

```bash
# 强调词必须是各自语言主文案的精确子串
node design/app-store-studio-2026-10-29/scripts/check-headline-highlights.mjs
# → OK 5 slides x 4 approved locales（--all 会因 8 种语言未翻译而失败，这是有意的）
```

- **36 张成品**（iPhone 20 + iPad 16，`exportedAt 2026-11-09T15:28+08:00`）：iPhone 1320 × 2868 + iPad 2064 × 2752，全部 mode RGB、无 alpha，SHA-256 见 `exported/export-validation.json`（`verified 36 / expected 36 / failures 0`，`files 20` + `ipadFiles 16`）。本轮重出 24 张（iPhone `04 / 05` + iPad `01 / 02 / 04 / 05`），随后 04 的接缝位置调整又重出 iPhone 4 张 + iPad 4 张 `04-diet.png`；每次改完都对全部 36 张重跑了尺寸 / mode / SHA-256 一致性复核，最近一次 36/36 通过
- 本轮起导出**不再走 Studio 的一键导出**，改用 `src/app/render/page.tsx` + headless Chrome 直接出原生像素：`"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --no-sandbox --hide-scrollbars --force-device-scale-factor=1 --window-size=<W>,<H> --virtual-time-budget=15000 --screenshot=<out.png> "http://localhost:3000/render?device=<dev>&slide=<id>&locale=<loc>"`，再把 PNG 以 `data:image/png;base64` + `artifactPath=ios/<device>/<W>x<H>/<locale>/<NN-slide>.png` POST 给 `/api/export-image`（服务端用 sharp 去 alpha、flatten 到 `#ebecec`，写进 `exports/latest/`）。`--screenshot` 不会等页面的 `data-ready` 标记，靠 `--virtual-time-budget` 兜；图片本身已被 `image-cache.ts` 预取成 data URI，所以渲染是确定性的。这条链路比 Studio 那条短、也不会被常驻标签页的旧 localStorage 污染
- 上一批（`final-dev5` + `final-ipad9`）的逐字节复核结论已部分作废：本轮 `04 / 05` 的 iPhone 图与 `01 / 02 / 04 / 05` 的 iPad 图都变了，其中 iPad `01 / 02` 的变化来自「单屏改成按画布比例」这一条，与业主这两条意见无关。**iPad 页不依赖 `slidesByDevice.ipad`**：`screenshot-editor.tsx` 的 `exportAll()` 里非 watch 的设备一律复用 `phoneSlides`（`const slides = size.device === "watch" ? [...] : phoneSlides`），所以 `app-store-screenshots.json` 里 `ipad` 一直是空数组是设计如此、不是丢页；但 iPad 只是把同一批 iPhone slide 按各自 spec 重排一次，`DeviceShowcase` 的固定构图会吃掉 `slide.transforms` / `slide.chat`，05 页 iPad 的扇形由 `fitLineup()` 把同一份 slots 缩进 `{90, 800, spec.w−180, spec.h−910}` 盒，所以 iPhone 侧一改 slot，iPad 侧跟着变（本轮已同步重出）
- 导出链路：Studio「一键导出」→ `/tmp/studio-out/<label>/ios/<device>/<size>/<locale>/` → `python3 docs/store-plan-a-2026-11-08/scripts/collect_plan_a.py`（`PASSES` 里按批次顺序追加、`IPAD_PASSES` 只有最新一版，`STALE` 清掉已撤下的页）→ 重写 `exported/export-validation.json`。导出时 locale / device 必须精确传 `"iPhone"`、`"iPad 13″"`（U+2033）、`"iPhone Duo"`、`"Apple Watch"`，且 `locales` 一定要显式传，默认只导 `zh`
- 另有两处**过程陷阱**记在这里，避免下次再来一遍：① Studio 的 autosave 会用常驻标签页的旧 state 覆盖 `app-store-screenshots.json`（`storage.ts` 先读 localStorage 再 fetch 文件，600ms debounce 后整份写回），所以改 JSON 前要先把标签页的 localStorage 清掉／把文件内容预写进缓存，改完再 `chmod 444` 保护；② 截图脚本必须用 `Emulation.setDeviceMetricsOverride(1440×9000)` 再取 `.studio-sheet` 的绝对坐标配 `captureScreenshot({clip, scale:2.2})`，混用 `captureBeyondViewport` 会得到空白图
- 画廊自检：`docs/store-gallery-2026-11-08/selftest.html` → **ALL PASS (31 checks)**，覆盖三批次切换、四语言、iPhone 5 页 / iPad 4 页切换、灯箱、矩阵视图与横向溢出（Plan A 批次现在有 iPhone 与 iPad 两个设备页签，`v=20261109a` 强刷缓存）

## 未完成 / 边界（做 12 语言前必须处理）

- **zh-Hant 动作名是机器翻译垃圾**：`exercises.json` 的 `name` 字段里 `bench_press_barbell` = 「座椅出版社（槓鈴）」、`bench_press_machine` = 「胸部出版社（器械）」、`lateral_raise_dumbbell` = 「平面升起（啞鈴）」。这批成品里**两页都暴露**：03 页手机与手表都写着「胸部出版社」（这是本轮新增的最大暴露面），05 页 iPad 的 `insights` 里还有「升降進度」与「座椅出版社（槓鈴）」；11-06 已上传的 312 张里同样存在。这是产品数据问题，不是截图问题——做繁中全量导出前必须先修一次繁中动作名（可能还有 ru / ar），或临时把 03 的动作换成繁中名正确的动作（要重拍手机 + 手表两组素材）、把 05 的 iPad 换成不含动作名的画面（如 `sleep`）。
- **zh-Hant 的 `diet` 截图缺餐食照片**（本轮发现）：`public/screenshots/localized/ipad/zh-Hant/diet.png` 与 zh / en / ja 同为 2064×2752，但「第 1 餐」那几张卡片只有日期 / 热量 / 三大营养素，**没有餐食缩略图**——zh 版有鸡胸西兰花、三文鱼沙拉两张。所以 zh-Hant 的 04 页 `04-diet.png` 只有 421KB，其余三语言都是 1.03MB 左右。这是**素材本身的内容缺口**（拍摄那天的合成数据里那一组餐没有配图），不是渲染问题：直接从源 PNG 裁同一区域就能确认，四语言的文件尺寸、mode 完全一致。修法是重拍一份带餐食照片的 zh-Hant `diet` 场景再覆盖该素材，然后重出该语言的 04（iPhone + iPad 各一张）。在那之前 04 的 zh-Hant 页在「三屏对照」时会被一眼看出内容比别的语言少。
- **05 的 Duo / Watch 图仍在待办**：iPhone 6.9″ × 4 语言（5 页）与 iPad 13″ × 4 语言（4 页，无 03）已进 `exported/`；iPad 现在是本轮按画布比例重出的版本，早期批次 `final-ipad5/6`（两排版）、`final-ipad7/8`（带胶囊或自绘边框）、`final-ipad9`（官方边框但单屏仍 1640 宽、双屏仍 1100 宽）都已被取代，别再引用。Duo 与 Watch 的 05 页尚未导出（Watch 单屏画布按现有规则不放四设备 lineup）；Duo 侧本轮已在 `/render?device=duo` 上核过构图（04/05 均不裁切、主文案单行），随时可按 iPhone 的同名文件重出。
- **手表系统时钟**：watchOS 顶部时钟无法用 `simctl status_bar` 覆盖（capture.sh 里仍会尝试，失败只打印原因继续），03 页手表显示拍摄时的真实时间（本轮成品里是 22:42），与手机被改成 09:41 的状态栏不一致；05 页右下的手表同样如此。属外观细节，未做像素修补——若要一致，只能重拍并把两只设备的拍摄时间凑到 9:41 附近，或接受这个差异。
- **8 种语言未翻译**：ko / es / fr / de / it / pt-BR / ru / ar 是英文占位，`approvedLocales` 只列四种，`pendingLocales` 记录待补清单。
- **未导出** iPad / Duo / Apple Watch 与新派生的 iPhone-medium。
- **未上传 App Store Connect**：线上仍是 11-06 批次。
- 转化验证只能在 App Store 产品页优化（A/B）做，最多 3 个处理组：只测首图（「今天练什么」vs「3D 恢复图」），其余不动。
