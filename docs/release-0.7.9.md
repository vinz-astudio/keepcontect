# Keep Contact 0.7.9

[Codex · 2026-09-27 01:39 +06:00]

本次修复原生活动时间真实性、通知快捷确认范围、后台上传恢复和退出后的推送解绑。详见 [机制修复记录](native-mechanism-repair.md)。

- Android：APK/AAB，versionCode 96；使用与 0.7.7 相同的签名证书。
- Windows：Tauri x64 EXE/MSI。
- iOS：0.7.9 (45)，GitHub Actions run 36266358600，Swift 回归、Xcode archive 和 TestFlight 上传成功；Apple 后续处理与设备安装尚未验证。
- 后端：三个 native mechanism/resume/push revocation 迁移已由 Supabase CLI 应用；notify-feed/push-dispatch 已部署，现有自定义鉴权保留。生产函数与 ACL 已读回确认。
- 验证：112 文件/677 测试、类型检查、前端构建通过；Android Java/JVM 与 release APK/AAB 构建通过；Windows Rust 测试和两个安装包构建通过。
- `npm run local:gate` 的产品检查通过；共享 Brain SDLC 检查仍报 Active Work 超过 12000 字符、包含 completed entry。未改动其他任务或放宽检查规则。
- 当前安装包不含嵌套安装器；APK 内 Web bundle 为 `index-D3pmgsUc.js`。文件大小与 SHA256 见 [产物清单](release-0.7.9-artifacts.json)。
- 这次验收不包含实体设备长时间待机、Google Play 上架审核或 macOS 安装包分发。

发布来源包含原生修复提交 `931fbf9` 和版本/CI 提交 `29c1e5b`。额外收录的 `20260921104852_harden_internal_rpc_execute.sql` 已在生产账本存在，本次没有重新执行；原文件字节保留。
