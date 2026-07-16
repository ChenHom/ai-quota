# AIQuota

AIQuota 是原生 SwiftUI macOS 選單列 App，讀取設定的 HTTPS `quota.json`，顯示 Codex、Claude、AGY 的 `5h`／`7d` 剩餘額度與重置時間。

開發過程的架構與技術決策，請見 [開發決策記錄](docs/development-decisions.md)。

## 功能

- 點選選單列圖示開啟 300 pt 寬的無色原生玻璃面板。
- 顯示各 Provider 的 5 小時、7 天額度、最後更新時間與重置時間。
- 重置時間固定顯示為 `MM/dd HH:mm`（例如 `07/22 04:50`）。
- 啟動、每 5 分鐘、手動重新整理時取得最新 JSON。
- 重新整理圖示至少順時針旋轉 0.3 秒；請求完成後立即停止。
- 右鍵選單提供「重新整理」及「結束 AIQuota」。

## 開發執行

以 Xcode 開啟 `Package.swift`，選擇 **My Mac** 後執行；或在完成 Xcode 授權後使用：

```bash
cd ~/code/ai-quota
swift run
```

首次使用前，系統必須信任 quota 站台使用的 mkcert 根憑證。若資料服務位於本機網路，請允許 AIQuota 存取本機網路；打包的 `Info.plist` 已包含用途說明。

## 設定資料端點

端點不會存入原始碼。打包後的 App 可使用下列指令設定本機 HTTPS URL：

```bash
defaults write com.example.aiquota quotaEndpoint -string "https://quota.example.invalid/quota.json"
```

開發時也可暫時以 `AIQUOTA_ENDPOINT` 環境變數提供端點。`swift run` 的裸執行檔沒有 bundle ID，會自動退回讀取打包版（`com.example.aiquota`）網域的 `quotaEndpoint`，因此打包版設定過一次即可。請勿提交實際內網 URL、憑證、私鑰、帳密或 Provider access token。

若端點位於內網 IP 或 `.local` 網域，首次開啟 App 時請允許 macOS 的「本機網路」權限；可在「系統設定 → 隱私權與安全性 → 本機網路」重新調整。

## 打包

執行：

```bash
./scripts/package.sh
```

打包會使用 release 建置，並移除二進位的非必要偵錯符號。產物位於 `dist/`：

- `AIQuota.app`：可直接執行的 macOS App bundle。
- `AIQuota-macos.zip`：可傳送或保存的壓縮檔。

目前產物未簽署與未公證。第一次開啟時若 macOS 阻擋，可在 Finder 對 App 按右鍵後選擇「打開」。
