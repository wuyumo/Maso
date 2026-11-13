# 全身负重粗估 v0.2

未验证的产品启发式，用来给**还没有重量**的动作一个保守起点。不是 1RM，不是实验结论，也不是安全上限。历史记录始终以千克保存；kg/lb 只影响显示。

## 公式

用户在一个已映射动作里亲手填入重量，并在**同一次训练**完成 **3 个不同的 8–12 次工作组**之后，该动作成为锚。

`推荐 = 真实锚重量 × 目标系数 / 锚系数 × 0.70`

0.70 只乘这一次，乘在真实重量上。估算结果带 `fullBodyRough` / `full-body-v0.2`，不能再当作锚。三次组的重量不同时，取**最轻**的那一组，不取最大。没有单独的热身标记；1–7 次或 13 次以上不计入这 3 组。

结果按器械向下取整：杠铃和 EZ 杆 2.5 kg，哑铃 1 kg。不足一档就保持空白，不会为了凑空杆而向上加。

性别只看资料里的男/女。未选择或「其他」分别用男女两列算出推荐，取更低的一个。没有第三套系数。

自己练过的记录、明确填过的重量（含 0）和逐组重量优先，不会被这条规则覆盖。

## 批准系数

背蹲 = 100。杠铃/EZ 含杆总重。哑铃按「每只」或「双手一只」，不是两只相加。

| 动作 | 男 | 女 | 目录 ID |
|---|---:|---:|---|
| 传统硬拉 | 115 | 120 | `deadlift` |
| 杠铃臀推 | 110 | 110 | `hip_thrust_barbell` |
| 背蹲 | 100 | 100 | `squat_barbell` |
| 罗马尼亚硬拉 | 80 | 80 | `rdl_barbell` |
| 前蹲 | 75 | 75 | `squat_front` |
| 杠铃平板卧推 | 70 | 60 | `bench_press_barbell` |
| 窄握卧推 | 60 | 50 | `bench_press_close_grip` |
| 严格俯身杠铃划船 | 60 | 50 | `barbell_row` |
| 约 30° 上斜杠铃卧推 | 55 | 48 | `incline_bench_press_barbell` |
| 站姿严格杠铃推举 | 40 | 35 | `overhead_press_barbell` |
| 单臂哑铃划船 | 35 | 30 | `dumbbell_row_single_arm` |
| 高脚杯深蹲（双手一只） | 35 | 35 | `squat_goblet` |
| 哑铃平板卧推（每只） | 28 | 24 | `bench_press_dumbbell` |
| 哑铃上斜卧推（每只） | 24 | 20 | `incline_bench_press_dumbbell` |
| EZ 杆弯举 | 24 | 20 | `bicep_curl_ez_bar` |
| 哑铃上拉（双手一只） | 24 | 20 | `dumbbell_pullover` |
| 双腿哑铃提踵（每只外加） | 24 | 24 | `calf_raise_standing_dumbbell` |
| EZ 仰卧臂屈伸 | 20 | 18 | `skullcrusher_ez_bar` |
| 哑铃坐姿推举（每只） | 18 | 15 | `overhead_press_dumbbell_seated` |
| 哑铃颈后臂屈伸（双手一只） | 18 | 16 | `overhead_extension_dumbbell_two_hand`，`overhead_extension_dumbbell_seated_two_hand` |
| 哑铃后撤箭步蹲（每只） | 15 | 15 | `lunge_reverse_dumbbell` |
| 哑铃弯举（每只） | 14 | 12 | `bicep_curl_dumbbell` |
| 锤式弯举（每只） | 14 | 12 | `hammer_curl` |
| 哑铃侧屈（一只） | 14 | 14 | `side_bend_dumbbell` |
| 哑铃飞鸟（每只） | 10 | 8 | `dumbbell_fly_flat` |
| 抱片卷腹（外加片） | 8 | 8 | `crunch_weighted` |
| 哑铃侧平举（每只） | 7 | 6 | `lateral_raise_dumbbell` |
| 哑铃反向飞鸟（每只） | 7 | 6 | `rear_delt_fly_dumbbell`，`rear_delt_fly_dumbbell_seated` |

共 28 个动作、30 个目录 ID。上斜卧推的目录名没有写明 30°，用的是标准杠铃上斜 ID，不是低角度或史密斯变体。

## 明确不映射

不给这些动作编千克：自重、弹力带、计时、TRX、器械、史密斯、绳索（含滑轮倍率）、壶铃、暂停/节奏/单腿/相扑/亏重等不同口径。例如 `squat_bodyweight`、`rdl_smith`、`bench_press_machine`、`hip_thrust_barbell_paused`、`push_press_barbell`、`deadlift_sumo`、`deadlift_deficit`、`squat_goblet_kettlebell`、`bicep_curl_cable`、`triceps_pushdown_straight_bar`、`lateral_raise_machine`。名称接近但借力方式或器械不同的，也不并进上表。

旧的卧推 6RM 人口公式和只含三个动作的粗估不再负责填空。个人真实历史仍然优先。
