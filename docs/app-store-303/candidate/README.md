# Masso 3.0.3 ASO text preparation — NOT APPLIED

用户pt432u批准定位后的实施准备；仅在box生成。没有创建ASC版本、填字段、保存、构建、上传、提审或发布。

- `after/en-US/` 与 `after/zh-Hans/`：五个已批准文本字段，可供后续人工或受支持工具逐字段使用。
- `before/`：从最新ASC只读转录直接提取的实际旧值，包含原What's New；旧promo为空文件。
- `rollback/`：before逐字复制，仅作恢复参考；不是绕过审核的一键回滚。
- `diffs/`：逐字段差异；zh-Hans/name未改，diff为空。
- `review-only/*/whats_new.txt`：仅准确描述商店信息更新的待审建议，不宣称新功能/修复；不在after应用集合，必须和最终build核对。
- `snapshots/asc-metadata-2026-11-19.txt`：父提供的最新ASC转录完整原件。描述不是从旧本地或公开抓取替代。
- `manifest.json`：来源、日期、范围、计数、SHA256、待决项。

描述只替换第一条功能bullet之前的介绍区域（旧口号+介绍段）。第一条bullet至结尾的功能、免费/Pro、额度、续订、恢复估算/非医疗、隐私链接及兼容导入限制全部逐字保留。未翻译其他10个locale。

离线只读检查：`python3 validate.py`。脚本不联网、不写文件、不调用ASC或shell子命令。
自测：`python3 validate.py --self-test`，仅内存变异，验证可发现篡改、错误定位、超限和尾部损坏。

真正应用前先重新读取ASC并比较before，若有他人变更则停止自动覆盖。名称副标题在App Information，其他文本在目标版本locale页；创建/选择3.0.3、新build、最终审核和发布均由父协调并按确认边界另行处理。类别、地区、其他locales和release settings不得触碰。
