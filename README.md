# 尿酸记录（UricLog）

一款免费、极简、隐私优先的尿酸数值记录与趋势查看 iOS App。

核心原则：只做“记录 + 趋势 + 可带走（导出）”，不提供医疗诊断与治疗建议。

## 功能概览

- 记录：新增/编辑/删除尿酸数值，支持测量时间与备注
- 单位：支持 `μmol/L` 与 `mg/dL`，可随时切换
- 参考范围：可按性别显示常见参考区间；提供“来源与引用”链接便于核对
- 趋势：按 7/30/90 天或全部查看趋势图与统计摘要；支持目标值
- 导出：支持导出 CSV（便于复诊或自行分析）
- 同步（可选）：支持 iCloud（CloudKit）同步数据；并通过 iCloud Key-Value Store 同步关键设置（性别、目标值等）

## 项目结构

- `UricLog/`
  - `UricLogApp.swift`：App 入口
  - `Views/`：SwiftUI 页面
    - `RecordsListView.swift`：记录列表
    - `RecordEditorView.swift`：新增/编辑记录；包含“参考信息/来源与引用”入口
    - `TrendsView.swift`：趋势图与统计
    - `SettingsView.swift`：单位、性别、目标值、iCloud、导出等设置
  - `Models/`：领域模型与设置 Key
    - `UricAcidRecord.swift`：Core Data 实体扩展与创建逻辑
    - `Unit.swift`：单位换算、性别参考范围、设置 Key（`AppSettingsKey`）
  - `Persistence/`：持久化与 iCloud
    - `Persistence.swift`：Core Data / CloudKit 容器构建
    - `PersistenceController.swift`：容器加载、iCloud 状态与同步事件
  - `Utils/`
    - `CSVExporter.swift`：CSV 导出
    - `DateFormatter.swift`：日期格式化
    - `ICloudSettingsSync.swift`：iCloud Key-Value Store 设置同步
- `doc/PRD.md`：产品说明（PRD）
- `site/privacy-policy.html`：隐私政策页面（用于上架资料）

## 本地运行

1. 安装依赖：`pod install`
2. 用 Xcode 打开 `UricLog.xcworkspace`
3. 选择 `UricLog` scheme
4. 运行到模拟器或真机

## iCloud 同步说明

- 记录数据：通过 CloudKit + Core Data（`NSPersistentCloudKitContainer`）同步
- 设置数据：通过 `NSUbiquitousKeyValueStore` 同步以下 Key
  - `userGender`
  - `targetEnabled`
  - `targetValue`
  - `preferredUnit`

开启入口在设置页的 iCloud 开关；关闭后本地仍可正常使用。

## 免责声明

本应用仅用于个人记录与参考，不构成医疗建议或诊断依据。如有异常请咨询专业医生。
