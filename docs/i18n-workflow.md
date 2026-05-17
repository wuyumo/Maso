# i18n Workflow — 多语言适配工作流

Maso 支持 12 种语言: en / zh-Hans / zh-Hant / ja / ko / es / fr / de / it / pt-BR / ru / ar.

每次加新 UI string, 走这个 workflow 保证 12 种语言同步:

---

## 日常工作流 (3 步)

### Step 1: 写 SwiftUI 代码

加 string literal 给 `Text` / `Button` / `Label` / `.navigationTitle` / `NSLocalizedString` — 这些 API 自动走 LocalizedStringKey 查表:

```swift
Text("Hide older workouts")         // ✓ 自动 i18n
Button("Save", action: save)         // ✓ 自动 i18n
.navigationTitle("Customize")        // ✓ 自动 i18n
NSLocalizedString("My Workout", comment: "")  // ✓ 显式查表

// ❌ String 类型变量 — 不走 i18n, 直接显示
let title = "Hello"
Text(title)  // 中文用户看英文!
```

**例外**: 用 String 变量时, 显式调 NSLocalizedString:
```swift
let key = data.someStringKey
Text(LocalizedStringKey(key))  // 或 NSLocalizedString(key, comment: "")
```

### Step 2: lint 检测缺失

```bash
python3 scripts/lint_translations.py
```

输出:
```
🔴 UNREGISTERED (3) — swift 用了字面量但 en.lproj 没 key:
  • "Hide older workouts"
      ↳ Maso/Views/Screens/HistoryScreen.swift

🟡 MISSING TRANSLATIONS — en 有但其它 lproj 漏:
  zh-Hans: 0 missing
  ja: 3 missing
  ...
```

CI 模式 (有问题 exit 1, 用 pre-commit / GitHub Actions):
```bash
python3 scripts/lint_translations.py --check
```

### Step 3: auto-translate 自动补 11 种语言

先把新 key 加到 **en.lproj/Localizable.strings** (这是 source of truth):

```
"Hide older workouts" = "Hide older workouts";
```

然后自动翻译其它 11 种:

```bash
export ANTHROPIC_API_KEY=sk-ant-xxx     # 申请: https://console.anthropic.com/
python3 scripts/auto_translate.py
```

成本: 每次几分钱 (Claude Sonnet 4, ~$0.001/key/lang).

Review diff:
```bash
git diff Maso/Resources/*.lproj/Localizable.strings
```

满意就 commit. 不满意手工改对应 lproj.

---

## 备选: OpenAI 后端

如果你有 OpenAI key 不想用 Anthropic:
```bash
export OPENAI_API_KEY=sk-xxx
python3 scripts/auto_translate.py --backend openai
```

GPT-4o-mini 也够用, 翻译质量略差但便宜.

---

## Dry-run 看效果

```bash
python3 scripts/auto_translate.py --dry-run
```

只打印, 不写入. 确认翻译质量再正式跑.

---

## 单语言修

想只补某个语言 (e.g. 只补日语):

```bash
python3 scripts/auto_translate.py --lang ja
```

---

## 特殊场景

### Exercise 名字 (873 个动作)

走 `Maso/Resources/zh-Hans.lproj/ExerciseNames.strings` (单独 strings table).
更新走 `scripts/translate_exercise_names.py` (基于关键词模式批量生成).

### Brand / 不需要翻译的 string

加到 `scripts/lint_translations.py` 顶部的 `SKIP_LITERALS` set:

```python
SKIP_LITERALS = {
    "MASO", "Maso", "PRO",
    "exercise-set",  # accessibility identifier
    ...
}
```

### Plural / Stringsdict

%d 复数形式 (e.g. "1 workout" vs "5 workouts") iOS 标准走 `.stringsdict` 文件.
当前 Maso 用简单 `%d workout(s)` 兼容多数语言, 没用 stringsdict.
后续如果需要精确复数: 单独写 `Localizable.stringsdict`.

---

## CI Integration (可选)

在 `.github/workflows/lint.yml` 加:

```yaml
- name: Check i18n
  run: python3 scripts/lint_translations.py --check
```

或 pre-commit hook (`.git/hooks/pre-commit`):
```bash
#!/bin/bash
python3 scripts/lint_translations.py --check || exit 1
```

---

## 总结流程

1. 加 swift literal (用 `Text("...")` 等支持 LocalizedStringKey 的 API)
2. `python3 scripts/lint_translations.py` 看漏什么
3. 把新 key 加到 `en.lproj/Localizable.strings`
4. `python3 scripts/auto_translate.py` 自动补 11 种语言
5. `git diff` review → commit

每次加 string 都 3-5 分钟全语言覆盖完成.
