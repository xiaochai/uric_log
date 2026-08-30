# PostHog 埋点说明

## 隐私约束

- 禁止上传尿酸数值、目标值、备注、测量日期、记录 ID 或设备中的个人信息。
- 禁止把错误对象和自由文本直接作为事件属性上传。
- 只允许使用本文档列出的枚举属性。
- Session Replay、控件自动采集和自动页面采集保持关闭。

## 公共事件

| 事件 | 触发时机 | 属性 |
| --- | --- | --- |
| `app_launched` | App 初始化完成 | 无 |
| `tab_selected` | 切换底部 Tab | `tab`: `records` / `trends` / `settings` |
| `storage_error_acknowledged` | 关闭存储初始化错误提示 | 无 |

## 记录

| 事件 | 触发时机 | 属性 |
| --- | --- | --- |
| `records_range_changed` | 修改记录列表时间范围 | `range`: `days7` / `days30` / `days90` / `all` |
| `record_add_tapped` | 点击新增按钮 | 无 |
| `record_opened` | 点击已有记录 | 无 |
| `record_editor_cancelled` | 取消新增或编辑 | `mode`: `create` / `edit` |
| `record_unit_selected` | 在编辑器选择单位 | `unit`: `umolL` / `mgdL` |
| `record_save_tapped` | 点击保存 | `mode`: `create` / `edit` |
| `record_saved` | Core Data 保存成功 | `mode`: `create` / `edit` |
| `record_save_failed` | Core Data 保存失败 | `mode`: `create` / `edit` |
| `extreme_value_warning_shown` | 显示异常数值确认框 | `mode`: `create` / `edit` |
| `extreme_value_save_cancelled` | 取消保存异常数值 | `mode`: `create` / `edit` |
| `extreme_value_save_confirmed` | 确认保存异常数值 | `mode`: `create` / `edit` |
| `record_delete_requested` | 从上下文菜单点击删除 | 无 |
| `record_delete_cancelled` | 取消删除确认 | 无 |
| `record_delete_confirmed` | 确认删除 | 无 |
| `record_deleted` | 删除操作保存完成 | 无 |
| `reference_info_opened` | 打开参考信息 | 无 |
| `reference_info_closed` | 关闭参考信息 | 无 |

## 趋势与设置

| 事件 | 触发时机 | 属性 |
| --- | --- | --- |
| `trends_range_changed` | 修改趋势时间范围 | `range`: `days7` / `days30` / `days90` / `all` |
| `preferred_unit_changed` | 修改默认单位 | `unit`: `umolL` / `mgdL` |
| `gender_setting_changed` | 修改性别设置 | 无，不上传具体选择 |
| `target_setting_toggled` | 切换目标值功能 | 无，不上传状态或目标数值 |
| `icloud_sync_toggled` | 切换 iCloud 同步 | 无 |
| `icloud_restart_hint_acknowledged` | 关闭重启提示 | 无 |

## 导出

| 事件 | 触发时机 | 属性 |
| --- | --- | --- |
| `export_range_changed` | 修改 CSV 导出范围 | `range`: `days7` / `days30` / `days90` / `all` |
| `csv_export_tapped` | 点击生成 CSV | `range`: 同上 |
| `csv_export_succeeded` | CSV 文件生成成功 | 无 |
| `csv_export_failed` | CSV 文件生成失败 | 无，不上传错误文本 |
| `csv_share_tapped` | 打开系统分享面板 | 无 |

## 新增事件规范

所有事件通过 `Analytics.track` 发送。新增事件前必须更新本文档，并确认属性不包含健康数据、自由文本、时间、唯一标识符或可用于重建用户记录的信息。
