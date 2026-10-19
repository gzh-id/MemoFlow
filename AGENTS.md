# MemoFlow 项目交接文档 — AGENTS.md

> 本文档是 Trae CN 接手 MemoFlow 项目的唯一权威指引。所有代码生成、修改、构建均以本文档为准。

---

## 一、项目概述

MemoFlow 是一款基于 HarmonyOS NEXT (API 24, SDK 6.1.1) 的智能备忘录应用，历经三个开发阶段：

| 阶段 | 目标 | 状态 |
|------|------|------|
| Phase 1 | 基础备忘录（数据模型 + RDB + UI 页面） | ✅ 已完成 |
| Phase 2 | 分布式协作（跨设备接续 + 购物清单同步） | ✅ 已完成 |
| Phase 3 | 元服务卡片 + 场景感知规则引擎 | ✅ 核心已完成 |
| Phase 3.3 | 会议纪要流转（录音 + 分布式推送 + 通知） | ✅ 已完成 |
| 后续优化 | 签名部署 + 集成测试 + 代码打磨 | ✅ 核心已完成 |

**当前构建状态**：`entry-default-unsigned.hap` 已成功生成（未签名）。签名材料（.jks + .cer）已生成，待配置 .p7b profile 后可签名部署。

---

## 二、硬性约束（不可违反）

### 2.1 SDK 与 API 版本
- **必须使用 HarmonyOS SDK 6.1.1 (API 24)**
- 导入统一使用 `@kit.*` 命名空间（如 `@kit.ArkData`、`@kit.FormKit`、`@kit.AbilityKit`）
- 禁止使用已废弃的 `@ohos.*` 导入方式

### 2.2 ArkTS 语法约束
- **禁止匿名对象字面量**：必须定义命名接口（`interface`），不能使用 `{ key: value }` 赋给未声明类型的变量
- **禁止未类型化的对象字面量**：所有变量必须显式声明类型
- **DataObject 类型转换**：定义接口时继承 `distributedDataObject.DataObject` 可避免 API 24 的类型转换错误
- **卡片数据扁平化**：服务卡片通过 `FormBindingData` 传递的数据必须为基本类型（string/number/boolean），禁止嵌套对象或数组

### 2.3 服务卡片进程约束
- **卡片运行在独立进程**，不能访问主应用的 ViewModel
- 卡片数据必须通过 `RdbHelper` 直接查询数据库获取
- `FormExtensionAbility` 中不能 import ViewModel 等主应用业务模块
- 卡片 UI 组件中不能使用 `@State`，只能使用 `@LocalStorageProp` 从 `formData` 接收数据
- 卡片 UI 中不支持 `LazyForEach`，只能用 `ForEach` 或静态条件渲染

### 2.4 分布式数据约束
- 分布式数据同步需要 `ohos.permission.DISTRIBUTED_DATASYNC` 权限
- `EntryAbility` 必须设置 `'continuable': true`
- 分布式对象不能直接存储类实例，Memo 对象必须序列化/反序列化
- UI 更新分布式数组变化时必须创建新数组引用：`this.items = [...this.items]`

### 2.5 文件系统 API
- `@kit.CoreFileKit` 导出的是 `fileIo`（不是 `fs`）
- 正确写法：`import { fileIo as fs } from '@kit.CoreFileKit'`
- `@kit.ArkData` 不导出 `util`，文本读取用 `fileIo.readTextSync()`

---

## 三、项目架构与文件清单

### 3.1 目录结构

```
entry/src/main/ets/
├── model.ets                      # Memo 数据模型
├── database.ets                    # RdbHelper 数据库操作（单例）
├── viewmodel.ets                   # MemoViewModel 业务逻辑（单例）
├── common.ets                      # 公共常量、枚举、工具类
├── entryability/
│   └── EntryAbility.ets            # 应用入口 Ability
├── entrybackupability/
│   └── EntryBackupAbility.ets      # 备份能力
├── pages/
│   ├── Index.ets                   # 导航入口（Navigation）
│   ├── MainPage.ets                # 主页面（列表 + 搜索 + 分类 + 场景模拟）
│   ├── EditPage.ets                # 编辑页面
│   ├── RecordPage.ets              # 会议录音 + 纪要生成页面
│   └── ShoppingListPage.ets        # 购物清单同步页面
├── distributed/
│   └── DistributedManager.ets      # 分布式数据对象管理（单例）
├── widget/
│   ├── WidgetCard.ets              # 服务卡片 UI（2x2 / 4x4）
│   ├── WidgetCardAbility.ets       # FormExtensionAbility
│   └── WidgetHelper.ets            # 卡片数据构建 + formId 管理
└── rules/
    └── RuleEngine.ets              # 场景感知规则引擎（单例）
```

### 3.2 配置文件

| 文件 | 路径 | 说明 |
|------|------|------|
| `module.json5` | `entry/src/main/module.json5` | 模块配置，含权限声明和扩展能力 |
| `form_config.json` | `entry/src/main/resources/base/profile/form_config.json` | 卡片配置 |
| `main_pages.json` | `entry/src/main/resources/base/profile/main_pages.json` | 页面路由 |
| `build-profile.json5` | 项目根 + entry 模块 | 构建配置 |
| `oh-package.json5` | 项目根 + entry 模块 | 依赖管理 |
| `string.json` | `entry/src/main/resources/base/element/string.json` | 字符串资源 |

### 3.3 权限声明（module.json5）

```json
"requestPermissions": [
  { "name": "ohos.permission.DISTRIBUTED_DATASYNC" },
  { "name": "ohos.permission.APPROXIMATELY_LOCATION" },
  { "name": "ohos.permission.LOCATION" },
  { "name": "ohos.permission.KEEP_BACKGROUND_RUNNING" }
]
```

### 3.4 扩展能力声明

```json
"extensionAbilities": [
  { "name": "EntryBackupAbility", "type": "backup" },
  { "name": "WidgetCardAbility", "type": "form", "metadata": [{ "name": "ohos.extension.form", "resource": "$profile:form_config" }] }
]
```

---

## 四、核心设计决策（不可推翻）

### 4.1 数据层
- **数据库**：`MemoStore.db`，SecurityLevel.S1
- **表结构**：`memo_table`（id, title, content, category, isCompleted, createTime）
- `isCompleted` 存储为 INTEGER (0/1)，读取时转 boolean
- `createTime` 使用毫秒时间戳
- 所有 SQL 参数化执行，禁止字符串拼接

### 4.2 状态管理
- 使用 V1 状态管理（`@Component` / `@State` / `@Consume` / `@Provide`）
- 列表使用 `LazyForEach` + `MemoDataSource`（实现 `IDataSource`）
- `ForEach` / `LazyForEach` 的 keyGenerator 使用业务 ID，不用数组索引

### 4.3 导航架构
- 单 `Navigation` + `NavDestination` + `navPathStack`
- 路由名通过 `RouteName` 枚举管理
- 页面间传参使用 `EditPageParam` 等命名类

### 4.4 单例模式
- `MemoViewModel`、`RdbHelper`、`DistributedManager`、`RuleEngine` 均为单例
- 单例通过 `static getInstance()` 获取，构造函数 `private`

### 4.5 卡片数据流

```
RDB → WidgetHelper.buildCardData() → formBindingData.createFormBindingData() → formProvider.updateForm()
                                                    ↓
                                    WidgetCard @LocalStorageProp 接收
```

- 卡片数据结构 `CardFormData` 为扁平化接口，所有字段为基本类型
- 购物清单前三项展开为 `item1Name`/`item1Checked`/`item2Name`/`item2Checked`/`item3Name`/`item3Checked`

---

## 五、可用技能与工具（务必使用）

### 5.1 deveco-cli 技能（构建验证首选）

```bash
# 安装
npm install -g @deveco/deveco-cli@latest

# 编译检查
devecocli build

# Lint 检查
devecocli check lint

# 文档搜索
devecocli docs search "关键词"
devecocli docs read <文档ID>
```

**规则：每次修改 .ets 文件后必须执行 `devecocli build` 验证编译通过。**

### 5.2 hmos-arkts-syntax-checker 技能

自动化语法检查 + 错误修复 + 循环构建。依赖 CodeGenie MCP Server。

错误优先级：
- **P0（必须修复）**：语法错误、类型错误、未定义变量、导入错误
- **P1（强烈建议）**：废弃 API
- **P2（可选优化）**：未使用变量、缺少异常处理

### 5.3 hmos-arkui-develop-skill 技能

ArkUI 代码开发助手。使用场景：
- 从零创建页面/组件
- 在现有 .ets 文件上增量修改
- 错误修复

**关键规则**：写代码前先查 `references/quick-apis/` 确认 API 参数，不凭记忆写。

### 5.4 hmos-arkts-knowledge-retriever 技能

ArkTS 文档检索，提供可追溯的 API 参考。当不确定 API 用法时先检索再写代码。

### 5.5 构建环境配置

```powershell
$env:DEVECO_SDK_HOME = 'D:\DevEco\DevEco Studio\sdk'
$env:JAVA_HOME = 'D:\DevEco\DevEco Studio\jbr'
$env:NODE_HOME = 'D:\DevEco\DevEco Studio\tools\node'
$env:PATH = 'D:\DevEco\DevEco Studio\tools\node;D:\DevEco\DevEco Studio\jbr\bin;C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem;' + $env:PATH
$env:COMSPEC = 'C:\Windows\System32\cmd.exe'

# 构建
& 'D:\DevEco\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default --no-daemon assembleHap
```

**产物路径**：`entry/build/default/outputs/default/entry-default-unsigned.hap`

---

## 六、待完成任务

### 6.1 Phase 3.3：会议纪要流转（可选高阶，面试加分项）

#### 6.1.1 录音与纪要生成模拟

创建 `pages/RecordPage.ets`：
- 使用 `@kit.AudioKit` 的 `audio.AudioRecorder` 录制音频
- 录制完成后模拟生成纪要文本（固定字符串即可）
- 将纪要保存为 Memo（category='meeting'）
- 通过 `DistributedManager` 推送到平板

**约束**：
- 音频 API 从 `@kit.AudioKit` 导入
- 录音权限 `ohos.permission.MICROPHONE` 需添加到 module.json5
- 录音页面需在 `main_pages.json` 中注册路由

#### 6.1.2 设备端流转提示

在 `MainPage.ets` 中监听分布式新会议纪要：
- 检测到 `category='meeting'` 的新备忘时发送本地通知
- 使用 `@kit.NotificationKit` 的 `notificationManager.publish()`
- 通知点击后跳转到 EditPage 查看
- 需添加 `ohos.permission.NOTIFICATION` 权限

### 6.2 签名配置

签名材料已生成，待完成 AGC 配置后可签名部署。

**已完成：**
- `signature/MemoFlow.jks` — 密钥库（RSA 2048，有效期 10 年，别名 MemoFlowKey，密码 123456）
- `signature/MemoFlow.cer` — 自签名证书

**待完成（需 Huawei Developer 账户）：**
1. 登录 [AppGallery Connect](https://developer.huawei.com/) 创建应用
2. 在 AGC 后台上传 `.cer` 证书或提交 CSR
3. 注册调试设备 UDID，下载 `.p7b` Profile 文件
4. 配置 `build-profile.json5` 中的 `signingConfigs`：
   ```json5
   "signingConfigs": [
     {
       "name": "default",
       "type": "HarmonyOS",
       "material": {
         "storeFile": "signature/MemoFlow.jks",
         "storePassword": "123456",
         "keyAlias": "MemoFlowKey",
         "keyPassword": "123456",
         "certpath": "signature/MemoFlow.cer",
         "profile": "signature/MemoFlow.p7b",
         "signAlg": "SHA256withRSA"
       }
     }
   ]
   ```
   > 注意：`certpath` 和 `profile` 必须全小写，`signAlg` 为必填项。

### 6.3 集成测试清单

| 测试项 | 场景 | 预期结果 | 代码路径 |
|--------|------|----------|----------|
| 基础备忘 | 创建/编辑/删除备忘录 | 数据持久化，列表刷新 | ✅ EditPage → RdbHelper → MainPage.onShown |
| 搜索 | 按关键词搜索 | 实时筛选结果 | ✅ MainPage.onChange → searchMemos |
| 分类筛选 | 切换分类标签 | 显示对应分类备忘 | ✅ MainPage.onClick → getMemosByCategory |
| 购物清单同步 | 两设备同时打开购物清单 | 实时同步勾选状态 | ✅ ShoppingListPage → DistributedManager |
| 跨设备接续 | 设备 A 编辑中切到设备 B | 弹出接续对话框 | ✅ EditPage → EntryAbility.onContinue → MainPage |
| 2x2 卡片 | 桌面添加卡片 | 显示待办数和优先备忘 | ✅ WidgetCardAbility → WidgetCard.Build2x2 |
| 4x4 卡片 | 桌面添加卡片 | 显示购物清单前三项 | ✅ WidgetCardAbility → WidgetCard.Build4x4 |
| 场景模拟 | 点击"场景"→"在超市" | 卡片切换为购物清单视图 | ✅ MainPage → RuleEngine → triggerFormUpdate |
| 卡片定时刷新 | 等待 updateDuration | 自动更新数据 | ✅ form_config updateDuration:1 → onUpdateForm |
| 卡片点击 | 点击卡片 | 打开主应用 | ✅ WidgetCard.onClick → postCardAction router |
| 会议录音 | 点击"录音"→ 录音 → 生成纪要 | 纪要保存为 Memo 并推送 | ✅ RecordPage → addMemo → pushMeetingMinutes |
| 会议纪要通知 | 其他设备推送会议纪要 | 保存 Memo + 本地通知 | ✅ MainPage.meetingMinutesCallback → notificationManager.publish |

### 6.4 代码质量优化

- ✅ 所有异步操作已添加 try-catch（MainPage.loadMemos/doDelete、EditPage.saveMemo/doDelete）
- ✅ 未使用的变量已删除（common.ets 无用类型别名、EntryAbility.KEY_IS_CONTINUATION）
- ✅ 确认无废弃 API 调用（所有导入使用 @kit.* 命名空间）
- ✅ 类型注解补全（EntryBackupAbility 返回类型、EntryAbility 常量和变量）
- ⬜ 深色模式：基础配置已有（start_window_background + form_config colorMode:auto），完整适配需将硬编码颜色迁移为 $color 资源引用

---

## 七、代码风格规范

### 7.1 命名约定

| 类型 | 约定 | 示例 |
|------|------|------|
| 类名 | PascalCase | `MemoViewModel` |
| 接口名 | PascalCase | `CardFormData` |
| 方法名 | camelCase | `loadAllMemos()` |
| 变量名 | camelCase | `currentCategory` |
| 常量 | UPPER_SNAKE | `STORE_CONFIG` |
| 枚举值 | UPPER_SNAKE | `SceneType.SHOPPING` |
| 文件名 | 与导出类同名 | `WidgetCard.ets` |

### 7.2 组件结构顺序

```typescript
@Component
export struct XxxPage {
  // 1. 状态变量
  @State data: Type = initialValue;

  // 2. 私有属性
  private viewModel: XxxViewModel = XxxViewModel.getInstance();

  // 3. 生命周期
  aboutToAppear(): void { }
  aboutToDisappear(): void { }

  // 4. 业务方法
  private async loadData(): Promise<void> { }

  // 5. @Builder 方法
  @Builder ItemBuilder(item: Type) { }

  // 6. build()
  build() { }
}
```

### 7.3 异步异常处理

所有 `async` 方法中可能抛出异常的操作必须 try-catch：

```typescript
static async queryAllMemos(): Promise<Memo[]> {
  try {
    // ...
    return result;
  } catch (e) {
    throw e as Error;
  }
}
```

### 7.4 注释规范

- 类和公开方法必须有 JSDoc 注释
- 注释写"为什么"，不写"是什么"
- 不添加引用当前任务的注释（如"用于 issue #123"）
- 不创建多余文档文件

---

## 八、API 使用速查（已验证可用）

### 8.1 已验证的正确导入

```typescript
// 数据库
import { relationalStore } from '@kit.ArkData';

// 卡片
import { formBindingData, formProvider, FormExtensionAbility } from '@kit.FormKit';

// 文件
import { fileIo as fs } from '@kit.CoreFileKit';

// 日志
import { hilog } from '@kit.PerformanceAnalysisKit';

// Ability
import { UIAbility, Want } from '@kit.AbilityKit';

// 分布式
import { distributedDataObject } from '@kit.DataDistributedKit';
```

### 8.2 卡片数据更新

```typescript
// 构建 → 绑定 → 推送
const data: CardFormData = await WidgetHelper.buildCardData(context, dimension, scene);
const formBinding: formBindingData.FormBindingData = formBindingData.createFormBindingData(data);
await formProvider.updateForm(formId, formBinding);
```

### 8.3 全局 UI 接口（必须通过 getUIContext 调用）

```typescript
// ✅ 正确
this.getUIContext().getPromptAction().showToast({ message: '...' });
this.getUIContext().showAlertDialog({ ... });

// ❌ 错误（ArkTS 中全局 router 等已废弃）
router.pushUrl({ url: '...' });
```

---

## 九、经验教训（踩坑记录）

1. `@kit.CoreFileKit` 导出 `fileIo` 不是 `fs`；正确写法 `import { fileIo as fs }`
2. `util` 不从 `@kit.ArkData` 导出；用 `fileIo.readTextSync()` 替代手动 buffer + TextDecoder
3. 卡片运行在独立进程，不能 import ViewModel，必须直接用 RdbHelper
4. 卡片数据必须扁平化，不能传数组/嵌套对象
5. 构建需要同时设置 DEVECO_SDK_HOME、JAVA_HOME(jbr)、NODE_HOME 和 System32 路径
6. `spawn cmd.exe ENOENT` 错误是 PATH 缺少 `C:\Windows\System32`
7. `spawn java ENOENT` 错误是 JAVA_HOME 未指向 DevEco 内置 jbr
8. ArkTS 中匿名对象字面量会编译报错，必须定义命名 interface
9. DataObject 类型转换错误可通过继承 `distributedDataObject.DataObject` 解决
10. `showToast` 等全局 UI 接口需通过 `this.getUIContext()` 调用
11. `build-profile.json5` 签名配置字段名注意大小写：`certpath` 和 `profile` 必须全小写，`signAlg` 为必填项
12. `devecocli signature generate` 需要先执行 `devecocli auth login` 登录华为账号；本地可用 keytool 生成 .jks 和 .cer，但 .p7b profile 必须从 AGC 获取

---

## 十、对接 Trae CN 的工作流程

### 10.1 每次修改后的验证流程

```
修改 .ets 文件 → devecocli build → 有错误？
                                    ├─ 是 → 修复 → 重新 build
                                    └─ 否 → 继续
```

### 10.2 新功能开发流程

1. 先查 `hmos-arkts-knowledge-retriever` 确认 API 用法
2. 设计方案，识别不确定点
3. 查 `references/quick-apis/` 确认组件参数
4. 生成代码
5. `devecocli build` 编译验证
6. 最多 3 轮修复
7. 通过后交付

### 10.3 卡片相关开发的特殊检查

由于卡片运行在独立进程，以下 API 限制必须二次确认：
- 卡片 UI 中不能用 `@State`，只能用 `@LocalStorageProp`
- 卡片中不支持 `LazyForEach`
- 卡片进程不能 import 主应用的 ViewModel
- `postCardAction` 是卡片专用 API，不能在主应用使用
- 卡片中不能使用 `@ohos.multimedia.audio` 等多媒体 API

---

## 十一、官方文档与参考资源

### 11.1 卡片开发

- ArkTS 卡片创建指南：https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-ui-widget-creation
- ArkTS 卡片生命周期管理：https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-ui-widget-lifecycle
- ArkTS 卡片主动刷新：https://device.harmonyos.com/en/docs/apiref/harmonyos-guides/arkts-ui-widget-active-refresh
- JS 卡片开发（Stage 模型）：https://developer.huawei.com/consumer/en/doc/harmonyos-guides/js-ui-widget-development

### 11.2 ArkTS 语言与状态管理

- TypeScript 到 ArkTS 迁移案例：https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-more-cases
- MVVM 模式 V2 状态管理：https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/arkts-mvvm-v2
- @Reusable 装饰器与组件复用：https://device.harmonyos.com/en/docs/apiref/harmonyos-guides/arkts-reusable
- 构建第一个 ArkTS 应用：https://device.harmonyos.com/en/docs/apiref/harmonyos-guides/start-with-ets-stage

### 11.3 卡片开发实践要点（来自社区经验）

- `onAddForm` 是同步接口，必须立即返回占位数据，真实数据通过 `formProvider.updateForm` 异步推送
- `onCastToNormalForm` 是临时卡片转正后回调，此时 formId 才是稳定的，应在此保存 formId
- 从 API 22 起支持 `reloadForms` / `reloadAllForms` 批量刷新，仅可在 UIAbility 中调用
- 卡片定时刷新由 `updateDuration`（单位：小时）控制，`scheduledUpdateTime` 为定点刷新时间
