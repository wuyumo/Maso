# t328：51已存在自动心率卡片，补原生完整路径证明

2026-11-13 Asia/Shanghai。未改产品Release逻辑，不需要为本需求另做52。

PlanPlayerScreen.swift:4053–4065已在普通warningPending转true时自动expanded=true，不要求hasEscalatedWarning；3959–3964保留长按切换，短按仍开设置。BodyActivityHealth.swift:299–319保持个人阈值、3次/15秒、有效连续样本、120秒提醒冷却；220–232须低于个人阈值70%持续3次/15秒才恢复，避免波动立即收回。产品这3文件SHA与已上传51完全相同，详见RECEIPT.json。

## 实际原生证明（第二轮2/2方法通过）

- 没传强制卡片flag；先正常128胶囊→通过真实monitor的持续185/个人180→自动卡片，AX值明确Above your reminder limit。
- 同时断言整屏escalated-background不存在：证明普通超阈值已自动展开，并非必须到207红色升级才展开。
- 短暂160时卡片不收回；短按打开设置，Cancel后正常返回。
- 长按手动收回后，继续高心率样本不会每采样重新展开；再长按仍能展开。
- 无Watch/无样本模拟链路8秒不误展开，无红色升级。
- 首轮无数据方法通过，自动方法在真实卡片已经出现后因AX标识被Button与多个Other继承而查询歧义失败；仅修测试为唯一Button，第二轮2/2通过。未为了测试改产品行为。

所有原图、SHA、时间、场景在native-evidence-manifest.json；autocard-contact.jpg仅审阅拼版，不是上传源。传感器输入为明确合成fixture，经真实生产policy/UI，不是真实Watch同步或医疗有效性测试。未测真实振动次数，源码的120秒冷却及状态变化驱动可证明非每个采样重复动画/触发。

本需求仅增加DEBUG输入延迟/短暂波动fixture和测试；没有新发行archive/upload、实体设备安装、购买、模型调用、提审或部署。截图前阶段12语手机红态+18张Watch已完成，剩余24张iPad/Duo因本优先需求暂缓，下一窄阶段继续，不冒称完成。
