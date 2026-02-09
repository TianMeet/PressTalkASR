# PressTalk ASR (macOS Menu Bar)

PressTalk ASR 是一个 macOS 状态栏语音转文字工具，核心交互为：

- 按住说话（默认 `Option + Space`）
- 松开结束并进入转写
- 自动复制结果（可选自动粘贴到前台应用）

项目使用纯 Swift/SwiftUI，面向低等待感和高可用性场景。

## 功能概览

- Menu Bar App（`MenuBarExtra`）+ 原生 Popover 主面板
- 全局热键按住说话（按下开始、松开结束）
- 右下角 HUD 悬浮反馈（Listening / Transcribing / Success / Error）
- OpenAI 转写双路线：
  - Upload Streaming（文件上传 + 增量显示 + 自动回退）
  - Realtime（WebSocket 模式）
- VAD 头尾静音裁剪（上传前减小体积、减少等待）
- 静音自动结束（Auto Stop on Silence）
- 每日时长与费用估算
- 本地缓存 API Key（设置页输入，掩码展示）

## 技术架构

### 1) 分层结构

- UI 层
  - `PressTalkApp`：应用入口与状态栏挂载
  - `PopoverRootView` + `PopoverViewModel`：主面板与交互控制
  - `SettingsView` + `SettingsWindowController`：设置窗口
  - `HUDView` + `FloatingHUDWindow`：悬浮 HUD
- 应用编排层
  - `AppViewModel`：状态机中枢、录音/转写主流程、错误处理、复制粘贴链路
- 音频处理层
  - `AudioRecorder`：录音与电平采样
  - `SilenceAutoStopDetector`：静音自动结束检测
  - `VADTrimmer`：头尾静音裁剪
- 云端转写层
  - `OpenAITranscribeClient`：文件转写（支持 streaming + fallback）
  - `RealtimeTranscribeClient`：Realtime WebSocket 转写
- 平台能力层
  - `HotkeyManager`：全局热键
  - `ClipboardManager`：复制/自动粘贴
  - `PermissionHelper`：麦克风/辅助功能权限

### 2) 关键状态流

- 录音会话主状态：`idle -> listening -> transcribing -> success/error -> idle`
- `AppViewModel` 统一收敛“手动 stop”和“静音 auto-stop”，确保同一会话只 stop 一次。
- Transcribing 阶段支持增量文本（delta）节流刷新 HUD，再以 done/最终文本覆盖。

## 转写路线设计

### 路线 A：Upload Streaming（默认）

- 松开后上传音频文件到 `/v1/audio/transcriptions`
- 请求 `stream=true`，增量展示转写文本
- streaming 不可用或失败时，自动回退到非流式一次性转写

适合：改造成本低、兼容性高、体感明显提速。

### 路线 B：Realtime（可选）

- 使用 `wss://api.openai.com/v1/realtime?intent=transcription`
- 发送 `session.update`（含 `server_vad` 参数）
- 按块 append 音频并接收 delta/done

适合：需要更快出字和更强“实时感”的场景。

说明：当前实现是“录音结束后将音频推送到 Realtime 通道转写”，不是边录边推流。如需“真正 ongoing recording 实时字幕”，可后续切换到 `AVAudioEngine` 实时采集管线。

## 音频与性能策略

- 录音格式优先：`m4a(AAC)`，失败自动降级到 `wav(PCM)`，提高兼容性
- 默认录音参数：单声道，低码率优先，降低上传时延
- 录音前后静音裁剪：减少无效字节与模型推理长度
- 静音自动结束：避免说完后手动等待
- HUD 增量文本刷新节流：降低 UI 抖动和主线程压力

## 配置项（Settings）

- API & Model
  - API Key（本地缓存）
  - 模型：`gpt-4o-mini-transcribe` / `gpt-4o-transcribe`
  - 转写路线：Upload Streaming / Realtime
  - Language：Auto / 中文 / English
  - Prompt（可配置最短时长门槛后发送）
- Behavior
  - Enable VAD Trim
  - Auto Paste
  - Auto Stop on Silence + 高级阈值
  - Realtime VAD 高级参数（silence duration / prefix padding）
- Permissions
  - Microphone / Accessibility 状态与跳转
- Cost
  - 今日累计时长与费用估算

## 模块对照（核心文件）

- 入口与窗口
  - `Sources/PressTalkASR/PressTalkApp.swift`
  - `Sources/PressTalkASR/AppDelegate.swift`
  - `Sources/PressTalkASR/SettingsWindowController.swift`
- 主业务编排
  - `Sources/PressTalkASR/AppViewModel.swift`
  - `Sources/PressTalkASR/AppSettings.swift`
- 转写与网络
  - `Sources/PressTalkASR/OpenAITranscribeClient.swift`
  - `Sources/PressTalkASR/RealtimeTranscribeClient.swift`
- 音频处理
  - `Sources/PressTalkASR/AudioRecorder.swift`
  - `Sources/PressTalkASR/VADTrimmer.swift`
  - `Sources/PressTalkASR/SilenceAutoStopDetector.swift`
- HUD 与 Popover
  - `Sources/PressTalkASR/HUDPresenter.swift`
  - `Sources/PressTalkASR/HUDStateMachine.swift`
  - `Sources/PressTalkASR/HUDView.swift`
  - `Sources/PressTalkASR/PopoverRootView.swift`
  - `Sources/PressTalkASR/PopoverViewModel.swift`
- 平台能力
  - `Sources/PressTalkASR/HotkeyManager.swift`
  - `Sources/PressTalkASR/ClipboardManager.swift`
  - `Sources/PressTalkASR/PermissionHelper.swift`
  - `Sources/PressTalkASR/CostTracker.swift`

## 构建与运行

### 环境要求

- macOS 13+
- Xcode 15+（或 Swift 6.2 Toolchain）
- 有效 OpenAI API Key

### SwiftPM

```bash
cd /Users/xingkong/Desktop/voice/PressTalkASR
swift build
swift run PressTalkASR
```

### Xcode

1. `File -> Open...` 选择 `Package.swift`
2. 选择 `PressTalkASR` scheme
3. Run 启动

## 权限要求

- Microphone：录音必需
- Accessibility：Auto Paste 必需

设置页内已提供直达系统设置入口。

## API Key 说明

- 当前实现为“本地缓存模式”（非 Keychain）
- UI 仅展示掩码，不默认回显明文
- 建议仅在受信任设备使用，必要时定期更换 Key

## 典型排障

- `AudioCodecInitialize failed`
  - AAC 编码器初始化失败；已内置自动回退 WAV
- `HALC_ProxyIOContext...skipping cycle due to overload`
  - 音频 I/O 过载；建议关闭高负载应用、降低调试日志
- `NSURLErrorDomain -1200 / TLS error`
  - 常见于代理或证书链问题（例如本地代理 127.0.0.1）
- `429 You exceeded your current quota`
  - 账户额度或账单限制导致，需到 OpenAI 控制台处理

## 建议监控指标

- TTFT（松开到第一段文字）
- TTD（松开到最终文本）
- 上传耗时、音频体积、重试率
- 失败类型分布（网络/鉴权/配额/超时）

## 后续可演进方向

- 真正“边录边转写”实时字幕（AVAudioEngine + 持续推流）
- 端到端追踪与指标看板（TTFT/TTD 可视化）
- 分段上传（超长录音、25MB 风险前置）
- Prompt 模板管理与术语词典版本化

