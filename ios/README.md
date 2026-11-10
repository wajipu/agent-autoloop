# AutoLoop（iOS）

agent-autoloop 的 iPhone 客户端：一个首页看中台的活，一个页签看云效的工作项。

## 已经有的

**首页（中台）** — 读 `/v1/state`，每 15 秒自动刷、也能下拉刷
- 「今日完成」主卡：完成轮数、在线 Agent、执行概况、最近 12 小时完成趋势、累计完成、今日 Token 和估算费用；用量仅统计已上报记录，点击卡片进入统计
- 首页层级：紧凑今日概览 → 待你处理（有卡片时显示）→ 当前任务 → 最近处理 → 可展开的 Agent 列表；暂停/恢复全部规则收在右上角菜单
- 当前任务：执行与排队数量、任务状态和当前步骤；无任务时显示一行空闲说明，不再展示三个零值面板
- 并发轮次：现在区域显示最多 4 条；更多时可直接查看全部。统计页按在跑、状态未知、排队分组，点每条看详情；排队轮次可取消，在跑轮次可请求停止，状态未知时检查接单程序连接
- 需要你决定：有待拍板的卡片才出现，点进去能直接选一个选项作答
- 最近处理：默认展示 3 条，可展开至最近 5 条；连续相同结果会合并成 `×41`，点进去看这一轮的时间线
- 完成提示：App 使用期间每 5 秒检查新完成任务，顶部显示任务名和「查看结果」；点击直接进入对应轮次，多个完成任务依次提示，每条 8 秒后收起。首次连接不补弹历史完成任务，回到前台时检查离开期间的完成情况
- 轮次详情：接单 Agent、开始/结束/用时、错误、触发事件、会话、`/v1/runs/<id>/why` 的时间线（规则版本 → 触发事件 → 领取 → 结束）
- 改动清单：结论里带「改动」块时单独列成结构化列表（仓库 / 提交 / 文件数 / 说明），见 `~/.agent-autoloop/work/changes/README.md`
- Agent：在线状态、所在电脑、用的 Agent
- 右上角图表按钮进「统计」：流程条形图、最近 12 小时、累计构成环形图、花费

**工作项（云效）**
- 缺陷 / 任务 / 需求 切换，按状态分组，搜索、状态下拉筛选、下拉刷新
- 详情：编号、状态、类型、负责人、创建/更新时间、正文（Markdown 渲染）、「在云效打开」

**设置**（根页只有两行，点进去分别是）
- 中台：地址、本人密钥（钥匙串）、测试连接
- 规则：列表、新增、编辑定时/提示词/派给/工作目录、停用启用（全表单，不碰 JSON）
- 规则运行操作：右侧菜单暂停、恢复或立即运行；暂停可填写原因和自动恢复时间，列表显示暂停状态与原因；规则页支持下拉刷新
- 立即运行先确认，按对象分事项的规则需要填写对象编号；提交成功只表示进入调度，实际执行结果到首页查看
- Agent：列表、新增、编辑类型/接单电脑/权限/命令、删除（被规则用着的不让删）
- 云效：企业下拉（KoKLam / 众流，自动带项目 id 和默认类型）、令牌（钥匙串）、默认类型、高级里的企业/项目 id

UI 全部用系统原生组件（`List` + `.insetGrouped`、`Form`、`ContentUnavailableView`、`.searchable`、`.refreshable`），
正文用 [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) 渲染。

规则暂停与停用不同：暂停保留配置和排队任务，不中断已运行任务；恢复后不会补接暂停期间错过的触发。停用则将规则移出启用配置。暂停中的规则需先恢复，才能立即运行。

## 跑起来

```bash
cd ~/.agent-autoloop/app/ios
xcodegen generate            # project.yml → AutoLoop.xcodeproj（会自动拉 SPM 依赖）
open AutoLoop.xcodeproj      # 选 iPhone 模拟器直接 Run
```

命令行装到已启动的模拟器（密钥走环境变量，不用手填）：

```bash
xcodebuild -project AutoLoop.xcodeproj -scheme AutoLoop -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug \
  -derivedDataPath build build

xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/AutoLoop.app
TOKEN="$(grep '^KOKLAM_YUNXIAO_ACCESS_TOKEN=' ~/.config/koklam/yunxiao.env | cut -d= -f2-)"
SIMCTL_CHILD_YUNXIAO_TOKEN="$TOKEN" \
SIMCTL_CHILD_HUB_URL=http://103.236.88.53:28081 \
SIMCTL_CHILD_HUB_KEY="<本人的密钥>" \
  xcrun simctl launch --terminate-running-process booted com.wajipu.autoloop
```

截图时想直接打开某条工作项：再加 `SIMCTL_CHILD_OPEN_SERIAL=MGMF-40`。

真机要签名：填上 `DEVELOPMENT_TEAM`（`CODE_SIGN_IDENTITY` 从 `-` 换成你的证书），重新 `xcodegen generate`。

中台是 http 的，`project.yml` 里开了 `NSAllowsArbitraryLoads` 才能连；以后中台上了 https 记得关掉。

密钥第一次用环境变量注入后会自动写进钥匙串，之后启动不用再带。收回：在中台上 `agent-autoloop key remove owner iphone`。

## 数据从哪来

- 中台：`GET {hub}/v1/state`，`Authorization: Bearer <本人的密钥>`
- 云效：`x-yunxiao-token` 直连 OpenAPI

```
POST /oapi/v1/projex/organizations/{org}/workitems:search
GET  /oapi/v1/projex/organizations/{org}/workitems/{编号}
```

云效默认指向 KoKLam（`68359a6af957ee9df431ecaa` / 项目 `854d2f7e0a466c8d4e3dd69c85`）。

费用按接单程序提供的参考金额汇总；Codex 使用实际模型的官方 Standard API 单价估算，缓存读取、30 分钟缓存写入分别计价，单次输入超过 272K 使用长上下文价。当前价格表核对于 2026-11-10，支持 GPT-6.1 Sol、GPT-6.1 Terra、GPT-6 Astra、GPT-6 Luna；未知模型或本地用量记录不完整时显示未估算，不推算为零。不含工具、加速或地域附加费用；参考金额不是实际账单。
