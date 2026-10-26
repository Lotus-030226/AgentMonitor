<p align="center">
  <img src="assets/brand/agent-monitor.svg" alt="Agent Monitor 標誌" width="112">
</p>

# Agent Monitor

原生 macOS AI Agent 與本機狀態監控 App。透過懸浮 HUD，隨時查看 Agent 用量與 Mac 狀態。

[English](README.md) · **繁體中文** · [简体中文](README.zh-CN.md)

[下載最新版本](https://github.com/Lotus-030226/AgentMonitor/releases/latest) · [1.1.0 Apple Silicon 安裝包](https://github.com/Lotus-030226/AgentMonitor/releases/download/v1.1.0/AgentMonitor-1.1.0-macOS-arm64.zip)

## 功能

- **Agent 活動：** 查看支援客戶端的額度、Token 用量、對話狀態與 CLI／Desktop 來源，包括 Claude Code 與 Codex。可用資料依客戶端與帳戶而異。
- **進行中對話：** 對話列表只顯示進行中的工作，包含等待批准的請求；已完成的對話保留在本機歷史紀錄。
- **懸浮 HUD：** 一次顯示兩個 Agent，其餘向下捲動；本機摘要隨 HUD 寬度調整，最多顯示四欄。停留在 Docker 摘要可預覽容器名稱、映像與狀態。
- **總覽：** 成對卡片使用相同寬度與高度，標題與圖表底部對齊。
- **系統狀態：** 查看 CPU、記憶體壓力、儲存空間、網路流量、電池與熱狀態，以及高資源用量程序。
- **六個頁面：** 在同一視窗切換總覽、程序、Docker、本機服務、Token 與對話。
- **本機服務：** 查看 TCP 監聽埠，包含 Docker 以外的服務。支援搜尋、暫停與手動更新，每 10 秒採樣。選擇 HTTP 或 HTTPS 才會開啟服務，不會自動探測網站。
- **選用客戶端 hooks：** 在 HUD 回應支援的批准請求。每次都需要明確選擇允許一次或拒絕。

## 安裝

需要 **macOS 14 以上**。目前下載包支援 **Apple Silicon（arm64）**。

1. 從版本頁下載 `AgentMonitor-1.1.0-macOS-arm64.zip`。
2. 解壓縮後，將 **Agent Monitor.app** 拖入「應用程式」。
3. 從「應用程式」開啟 App。

App 使用 ad-hoc 簽署，沒有 Developer ID 憑證，也未經 Apple 公證。若 macOS 阻擋，請先核對下載來源；確認信任後，可到「系統設定 → 隱私權與安全性 → 強制打開」。

## 使用

開啟懸浮 HUD 查看 Agent 詳情與本機摘要，點擊摘要項目即可開啟詳情頁。App 沒有狀態列圖標；重新開啟 App 會顯示主視窗。

| 快捷鍵 | 動作 |
| --- | --- |
| `⌘1` | 開啟總覽 |
| `⌘,` | 開啟設定 |
| `⌘⌥H` | 顯示或隱藏主 HUD |
| `⌘Q` | 結束 App |

請在各供應者已安裝的客戶端登入。Agent Monitor 使用既有本機帳戶，沒有獨立帳戶或憑證輸入畫面。Claude Code 可先執行 `claude auth login`，再以 `claude auth status` 檢查，最後回到 Agent Monitor 設定重新整理。即使額度無法取得，仍可能顯示對話活動。

首次啟動預設關閉客戶端 hooks 與登入時啟動。需要時，在「設定 → 通用 → Client hooks」啟用；各客戶端的支援範圍不同。

本機監控只讀取系統狀態，不控制服務或容器。Agent 用量供應者可能使用客戶端既有憑證查詢遠端用量。資料來源、請求與儲存方式見[資料存取說明](docs/data-access.md)。無法取得的讀數會標示為未知或無法使用。

## 更新

在「Agent Monitor → 檢查更新…」或「設定 → 通用」手動檢查。自動檢查預設開啟：啟動時檢查，每 24 小時最多一次。需要時可在「通用」關閉自動檢查。

有較新的穩定版本時，設定與展開的 HUD 會顯示通知。你可以開啟版本頁或下載 ZIP；點擊後才會開始下載。App 不會自動安裝或取代自身。

更新時，先結束 Agent Monitor，解壓縮新 ZIP，再取代「應用程式」內的 **Agent Monitor.app**。原有偏好設定會保留。

檢查使用此儲存庫的官方 GitHub API，不使用供應者憑證、Cookie 或驗證資訊。GitHub 會收到 IP 位址與客戶端標頭等一般連線資訊，不會收到對話內容或系統讀數。詳見[更新資料存取](docs/data-access.md#update-checks)。

## 從原始碼建置

需要 macOS 14 以上，以及支援 Swift 6 的 Xcode。在專案資料夾執行：

```sh
scripts/build-app.sh release
open "build/Agent Monitor.app"
```

腳本會建立 App、包含資源與授權聲明，並進行 ad-hoc 簽署。它只為目前程序選擇已安裝的 Xcode，不修改系統選擇。

## 授權與致謝

以 [Agent HUD Open](https://github.com/jazzenchen/agent-hud-native-open) 為基礎，版本資訊見[上游說明](docs/UPSTREAM.md)。

本專案為 Lotus 維護的修改版本。專案程式碼與原創 Agent Monitor 標誌使用 [Apache License 2.0](LICENSE)。[NOTICE](NOTICE) 保留本專案與上游署名。第三方資源各有授權條款，見 [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)。產品名稱與第三方標誌屬於各自的權利人。
