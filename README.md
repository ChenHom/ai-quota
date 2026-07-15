# AIQuota

AIQuota 是原生 SwiftUI macOS 選單列 App，讀取設定的 HTTPS `quota.json`，顯示 Codex、Claude、AGY 的 `5h`／`7d` 剩餘額度與重置時間。

開發過程的架構與技術決策，請見 [開發決策記錄](docs/development-decisions.md)。

## 功能

- 點選選單列圖示開啟 300 pt 寬的無色原生玻璃面板。
- 顯示各 Provider 的 5 小時、7 天額度、最後更新時間與重置時間。
- 啟動、每 5 分鐘、手動重新整理時取得最新 JSON。
- 重新整理圖示至少順時針旋轉 0.3 秒；請求完成後立即停止。
- 右鍵選單提供「重新整理」及「結束 AIQuota」。

## 開發執行

以 Xcode 開啟 `Package.swift`，選擇 **My Mac** 後執行；或在完成 Xcode 授權後使用：

```bash
cd ~/ai-quota
swift run
```

首次使用前，系統必須信任 quota 站台使用的 mkcert 根憑證。

## 設定資料端點

端點不會存入原始碼。打包後的 App 可使用下列指令設定本機 HTTPS URL：

```bash
defaults write com.example.aiquota quotaEndpoint -string "https://quota.example.invalid/quota.json"
```

開發時也可暫時以 `AIQUOTA_ENDPOINT` 環境變數提供端點。請勿提交實際內網 URL、憑證、私鑰、帳密或 Provider access token。

## 打包

執行：

```bash
./scripts/package.sh
```

打包會使用 release 建置，並移除二進位的非必要偵錯符號。產物位於 `dist/`：

- `AIQuota.app`：可直接執行的 macOS App bundle。
- `AIQuota-macos.zip`：可傳送或保存的壓縮檔。

目前產物未簽署與未公證。第一次開啟時若 macOS 阻擋，可在 Finder 對 App 按右鍵後選擇「打開」。
