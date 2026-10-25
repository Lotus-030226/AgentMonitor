<p align="center">
  <img src="assets/brand/agent-monitor.svg" alt="Agent Monitor 标志" width="112">
</p>

# Agent Monitor

原生 macOS AI Agent 与本机状态监控 App。通过悬浮 HUD，随时查看 Agent 用量与 Mac 状态。

[English](README.md) · [繁體中文](README.zh-TW.md) · **简体中文**

[下载最新版本](https://github.com/Lotus-030226/AgentMonitor/releases/latest) · [1.0.0 Apple Silicon 安装包](https://github.com/Lotus-030226/AgentMonitor/releases/download/v1.0.0/AgentMonitor-1.0.0-macOS-arm64.zip)

## 功能

- **Agent 活动：** 查看支持客户端的额度、Token 用量、会话状态与 CLI／Desktop 来源，包括 Claude Code 与 Codex。可用数据因客户端与账户而异。
- **悬浮 HUD：** 一次显示两个 Agent，其余向下滚动；本机摘要保持可见。悬停于 Docker 摘要可预览容器名称、镜像与状态。
- **系统状态：** 查看 CPU、内存压力、存储空间、网络流量、电池与热状态，以及高资源用量进程。
- **六个页面：** 在同一窗口切换总览、进程、Docker、本机服务、Token 与会话。
- **本机服务：** 查看 TCP 监听端口，包含 Docker 以外的服务。支持搜索、暂停与手动刷新，每 10 秒采样。选择 HTTP 或 HTTPS 才会打开服务，不会自动探测网站。
- **可选客户端 hooks：** 在 HUD 回应支持的批准请求。每次都需要明确选择允许一次或拒绝。

## 安装

需要 **macOS 14 或更高版本**。目前下载包支持 **Apple Silicon（arm64）**。

1. 从版本页下载 `AgentMonitor-1.0.0-macOS-arm64.zip`。
2. 解压后，将 **Agent Monitor.app** 拖入“应用程序”。
3. 从“应用程序”打开 App。

App 使用 ad-hoc 签名，没有 Developer ID 证书，也未经过 Apple 公证。如果 macOS 阻止打开，请先核对下载来源；确认信任后，可前往“系统设置 → 隐私与安全性 → 仍要打开”。

## 使用

打开悬浮 HUD 查看 Agent 详情与本机摘要，点击摘要项目即可打开详情页。App 没有菜单栏图标；重新打开 App 会显示主窗口。

| 快捷键 | 操作 |
| --- | --- |
| `⌘1` | 打开总览 |
| `⌘,` | 打开设置 |
| `⌘⌥H` | 显示或隐藏主 HUD |
| `⌘Q` | 退出 App |

请在各提供商已安装的客户端登录。Agent Monitor 使用现有本机账户，没有独立账户或凭证输入界面。Claude Code 可先运行 `claude auth login`，再用 `claude auth status` 检查，最后回到 Agent Monitor 设置刷新。即使额度无法获取，仍可能显示会话活动。

首次启动默认关闭客户端 hooks 与登录时启动。需要时，在“设置 → 通用 → Client hooks”启用；各客户端的支持范围不同。

本机监控只读取系统状态，不控制服务或容器。Agent 用量提供商可能使用客户端现有凭证查询远程用量。数据来源、请求与存储方式见[数据访问说明](docs/data-access.md)。无法获取的读数会标为未知或不可用。

## 从源码构建

需要 macOS 14 或更高版本，以及支持 Swift 6 的 Xcode。在项目文件夹运行：

```sh
scripts/build-app.sh release
open "build/Agent Monitor.app"
```

脚本会构建 App、包含资源与许可声明，并进行 ad-hoc 签名。它仅为当前进程选择已安装的 Xcode，不修改系统选择。

## 许可与致谢

基于 [Agent HUD Open](https://github.com/jazzenchen/agent-hud-native-open)，版本信息见[上游说明](docs/UPSTREAM.md)。

本项目为 Lotus 维护的修改版本。项目代码与原创 Agent Monitor 标志使用 [Apache License 2.0](LICENSE)。[NOTICE](NOTICE) 保留本项目与上游署名。第三方资源各有许可条款，见 [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)。产品名称与第三方标志属于各自的权利人。
