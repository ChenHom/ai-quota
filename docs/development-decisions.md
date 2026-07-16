# AIQuota 開發決策記錄

最後更新：2026-07-16

## 目標與目前架構

AIQuota 是一個 macOS 選單列 App。它不直接向 Codex、Claude、AGY 請求額度，也不保存 Provider 帳密；它只讀取設定的 Collector URL 所產生的最新 JSON：

```text
各 Provider 額度來源
        ↓
Collector（每 5 分鐘）
        ↓
quota.json（原子替換）
        ↓
HTTPS 靜態站台
        ↓
AIQuota macOS App（啟動、每 5 分鐘、手動重新整理）
```

目前 App 使用 SwiftUI 顯示內容，AppKit 管理選單列與透明浮動面板。它顯示 Codex、Claude、AGY 的 `5h`／`7d` 剩餘額度、重置時間、來源最後更新時間與狀態。

## 決策總覽

| 問題 | 最終作法 | 為什麼這樣做 | 主要取捨 |
|---|---|---|---|
| 需要額度資料給多個客戶端 | Collector 產生靜態 JSON | 第一版不需要完整 API、資料庫或推播 | 簡單，但非即時 |
| JSON 更新可能被讀到半截 | 暫存檔後原子替換 | 確保讀者只得到完整舊版或新版 | 要求同一檔案系統 |
| Provider 資料不是每一種額度都有 | `five_hour`／`seven_day` 使用 Optional | 真實資料可為 `null`，不應偽造 0% | UI 要處理缺值 |
| 內網 HTTPS 請求失敗 | 信任 mkcert 根憑證 | 保留 URLSession 的正常 TLS 驗證 | 每台裝置要安裝信任根憑證 |
| Web/跨平台框架發行檔太大 | 改用 SwiftUI/AppKit | 只需 macOS 選單列與讀 JSON | 失去跨平台性 |
| Popover 遮住桌面，玻璃沒有質感 | 透明 `NSPanel` + SwiftUI `glassEffect` | 讓玻璃有真正可取樣的桌面背景 | 要自行處理定位與點擊外部關閉 |
| 原生玻璃不想帶深色或指定顏色 | 外層使用 `.glassEffect(.clear)` | 保持系統原生材質、避免額外色彩填滿 | 最終對比受桌布與系統設定影響 |
| 重新整理圖示太快或無法停止 | 最短 0.3 秒 + `TimelineView` | 讓動作可見且能立即停轉 | 載入時會以影格更新角度 |
| 希望三個 Provider 一次看完 | 不使用捲軸，面板依內容高度配置 | 選單列工具應快速掃讀 | 300 pt 寬度使版面較緊湊 |
| 發行檔案大小 | release build 後 `strip -S`，輸出 ZIP | 保留可開啟的 `.app`，同時縮小體積 | 目前未簽署與公證 |

---

## 1. HTTPS 內網憑證導致 `fetch failed`

### 現象

Collector 資料位於私有 HTTPS 網址。終端機使用：

```bash
curl --insecure https://quota.example.invalid/quota.json
```

可取得 JSON，但 App 的 `URLSession` 回報 `fetch failed` 或憑證相關失敗。這不代表 JSON 格式錯誤；多半是 TLS 信任鏈未通過。

`--insecure` 的意思是 curl 刻意忽略憑證驗證。它適合診斷「站台是否有回應」，但不能作為正式解法。

### 根本原因

HTTPS 連線會依序驗證：

1. 伺服器憑證是否仍有效。
2. 憑證名稱是否涵蓋目前使用的主機名稱或 IP；該位址必須位於 SAN。
3. 簽發該憑證的根憑證或中繼憑證，是否可由 macOS Keychain 信任。

內網常使用 mkcert 自建 CA。若 Mac 沒有信任 mkcert 的根憑證，或憑證沒有包含 IP 的 SAN，macOS 的 URLSession 就會拒絕連線。這是預期的安全行為。

### 採用方案：信任私有 CA，而不關閉驗證

在每台要執行 AIQuota 的 Mac 上，匯入 Collector 使用的 mkcert 根憑證到 Keychain 的 **System** keychain，並設定為信任。伺服器端必須用同一個 CA 簽發憑證，且憑證 SAN 必須包含實際請求的位址。

這讓 App 仍採用標準 URLSession 與系統 TLS 驗證；程式不需要儲存或忽略任何憑證例外。

### 為什麼不在程式裡忽略憑證錯誤

可以透過 `URLSessionDelegate` 接受所有 server trust challenge，或把 App Transport Security 放寬，但這會讓中間人攻擊也可能被接受。尤其額度資料若涉及帳號使用狀態，不應為了方便而完全跳過憑證驗證。

| 作法 | 優點 | 缺點與適用情況 |
|---|---|---|
| 信任 mkcert 根憑證（目前） | 內網 TLS 正常驗證、成本低 | 每台客戶端要安裝根憑證；適合個人／受控設備 |
| 公開 CA 憑證 | 不需手動安裝根憑證 | 需可公開驗證的網域；適合正式對外服務 |
| Tailscale／VPN + 私有 DNS | 網路邊界更清楚，服務不必公開 | 要管理 VPN 與裝置加入；適合個人多裝置 |
| Cloudflare Access 等存取閘道 | 可做登入、存取政策與稽核 | 架構與營運成本較高；適合團隊服務 |
| App 忽略憑證驗證 | 最快讓開發環境連線 | 不安全，不應使用於正式版本 |

### 驗收方式

- 不使用 `--insecure` 的 `curl https://quota.example.invalid/quota.json` 可成功。
- App 手動重新整理後不顯示「更新失敗」。
- 若改用不在 SAN 中的 IP／網域，應被拒絕；這表示名稱驗證仍然有效。

---

## 2. `NSPopover` 顯示為深色底板，玻璃取樣不到桌面

### 現象

初版以 `NSPopover` 承載 SwiftUI 面板。即使 SwiftUI 內容套用 `glassEffect` 或 `NSVisualEffectView`，畫面仍像不透明深灰框，甚至有 Popover 的箭頭。這與 macOS 控制中心那種能看見桌布細節的玻璃外觀不同。

### 根本原因

視圖層級可簡化為：

```text
NSStatusItem
  └─ NSPopover 的系統視窗與箭頭背景
       └─ NSHostingController
            └─ SwiftUI glassEffect
```

`NSPopover` 不是單純透明容器。它先繪製系統管理的背景與箭頭，再放入 SwiftUI 內容。內容中的玻璃材質因此主要「看到」的是 Popover 的深色背景，而不是桌布。把 Hosting View 背景設成 `clear` 仍不足以移除這一層。

### 採用方案：透明無框 `NSPanel`

改用以下 AppKit 設定：

- `.borderless`：不繪製一般視窗邊框。
- `.nonactivatingPanel`：點選面板不強制搶走前景 App 焦點。
- `isOpaque = false`、`backgroundColor = .clear`：允許 SwiftUI glass 直接和桌面合成。
- `.popUpMenu` window level：顯示在一般 App 視窗上方。
- `collectionBehavior` 包含 `.canJoinAllSpaces`、`.fullScreenAuxiliary`：跨 Space 與全螢幕情境較合理。

面板會依狀態列按鈕的螢幕座標自行定位，並以 local/global event monitor 在點擊外部時關閉。

### 優點與代價

| 項目 | `NSPanel`（目前） | `NSPopover` |
|---|---|---|
| 背景透明度與玻璃取樣 | 可完全控制 | 系統底板會介入 |
| 箭頭 | 無箭頭 | 有原生錨點箭頭 |
| 位置 | 自行依 Status Item 計算 | 系統自動定位 |
| 點擊外部關閉 | 必須自行監聽事件 | `.transient` 自動處理 |
| 跨螢幕／全螢幕細節 | 需自行測試與維護 | 系統處理較完整 |
| 視覺自由度 | 高 | 中等 |

### 其他可選方案

- **保留 `NSPopover`，接受系統底板**：程式最少，適合不追求桌面玻璃效果的工具。
- **使用一般 `NSWindow`**：控制力相近，但要額外處理啟用、關閉與視窗層級；對此用途不比 `NSPanel` 合適。
- **完全 SwiftUI `MenuBarExtra`**：程式較少，但彈出樣式由系統控制，無法保證透明面板的效果。

### 風險與驗收

自訂 Panel 的主要風險不是繪製，而是互動：多顯示器、全螢幕 App、Space 切換及外部點擊關閉都需實機檢查。目前實作已保留右鍵選單的「重新整理／結束 AIQuota」，且左鍵可開關 Panel。

---

## 3. 想要原生玻璃但不想要顏色

### 容易混淆的三件事

1. **`Color.clear`**：完全不繪製背景，不會產生玻璃的模糊、高光與邊界。
2. **`Glass.regular`**：macOS 原生玻璃，但系統會依亮／暗模式、背景與可讀性自動帶入較明顯的材質對比。
3. **`Glass.clear`**：仍是 macOS 原生玻璃效果，但不額外指定 tint，是最符合「沒有額外顏色」的選擇。

初版使用 `.regular` 時，即使程式碼沒有寫紫色、藍色或灰色，系統仍可能在深色背景上呈現深灰材質。Provider 卡片若再各自套一層材質，視覺上會變成三張深色卡片。

### 採用方案

- 外層面板使用 `glassEffect(.clear, in: RoundedRectangle(...))`。
- Provider 卡片不再套玻璃填色，只保留透明內容與淡白色細邊框。
- 進度條採用半透明白色，不使用紫色漸層。

這保留玻璃的可讀性、高光、折射與系統整合感，但避免 App 自行增加一層顏色。

### 為什麼仍可能看起來偏深或偏淺

玻璃不是固定 RGBA 顏色。macOS 會根據下面因素合成：

- 目前桌布或背後的 App 視窗。
- macOS 亮色／暗色模式。
- 使用者是否開啟「減少透明度」或增加對比。
- 系統為確保文字可讀性而加入的自動對比。

因此「無色」應理解為程式不加入指定 tint，不代表每個桌布下都完全透明或完全一致。

| 方案 | 優點 | 缺點 |
|---|---|---|
| `.glassEffect(.clear)`（目前） | 原生、無指定色彩、保留材質感 | 視覺隨環境變化 |
| `.glassEffect(.regular)` | 對比與可讀性通常更強 | 可能看似有深灰／淺灰底色 |
| 固定 `Color.black.opacity(...)` | 每台畫面一致、容易設計 | 不再是純原生玻璃，且可能遮住桌布 |
| 完全 `Color.clear` | 最透明 | 幾乎沒有玻璃可讀性與邊界感 |
| `NSVisualEffectView` | 可支援較舊 macOS | 視覺較接近傳統 Vibrancy，不是 macOS 26 的新 Glass API |

### 可讀性取捨

若未來發現白色文字在淺桌布上不清楚，可只提高文字陰影或邊框對比，而不要直接把整片改成黑色。這能保留無色玻璃的設計目標。

---

## 4. Electron DMG 過大

### 現象與根本原因

Electron App 不只是 App 的 HTML、CSS、JavaScript。每個發行檔還會包含：

- Chromium 渲染引擎。
- Node.js runtime。
- Electron 主程序與原生模組。
- App 的前端資源及打包器的額外檔案。

即使 AIQuota 的功能只有顯示幾行文字和向一個 URL 取 JSON，Electron 仍需要攜帶完整瀏覽器與 JavaScript runtime。這是 Electron 能跨平台的代價，不是單純刪除程式碼就能消除的大小。

### 採用方案：Swift Package release App bundle

改為 SwiftUI/AppKit 後，App 直接使用 macOS 已經提供的 SwiftUI、AppKit、Foundation 與 URLSession framework。這些系統 framework 不需被複製到 App 裡。

打包流程：

```text
swift build -c release
        ↓
複製二進位與最小 Info.plist 至 AIQuota.app
        ↓
strip -S 移除非必要偵錯符號
        ↓
以 ZIP 封裝 AIQuota.app
```

實測標準 release binary 加 `strip -S` 後，執行檔約 328 KB、App bundle 約 336 KB、ZIP 約 84 KB。曾測試 `-Osize`，此專案反而略大，因此採用標準 release 最佳化加 strip。

### 為什麼不優先產生 DMG

DMG 提供掛載磁碟、拖曳安裝版面與背景圖片等發布體驗，但 AIQuota 是單一小型 `.app`，ZIP 已能完整保留 App bundle。ZIP 比 DMG 更直接且大小更小。

| 發行格式 | 優點 | 缺點 | 適用時機 |
|---|---|---|---|
| App ZIP（目前） | 體積最小、製作簡單、易傳送 | 沒有拖曳安裝引導 | 個人／內網工具 |
| DMG | macOS 使用者熟悉，可加入 Applications 捷徑與視覺引導 | 增加包裝與維護成本 | 對外發布桌面 App |
| `.pkg` Installer | 可做安裝位置、權限、更新與企業部署 | 最複雜，通常需簽署 | 企業／受管裝置 |
| Homebrew Cask | 使用者更新方便 | 需要發布與維護 tap | 開發者工具、公開發布 |

### 優缺點與後續

Swift 原生包的優點是小、快速、與 macOS 選單列／Glass API 整合自然；缺點是只能運行於 macOS，並需維護 Apple 平台程式碼。

目前包未使用 Developer ID 簽署或 Apple notarization，因此 Gatekeeper 可能要求使用者右鍵選「打開」。若要正式對外發布，應加入簽署、公證與版本更新策略；這會增加 Apple Developer Program、CI 憑證管理與發行流程成本。

## 公開儲存庫的資料邊界

以下內容不可放入 Git repository：

- 實際內網 URL、IP、DNS 名稱與網路拓撲。
- mkcert 根憑證、伺服器憑證、私鑰與簽署檔案。
- Provider 帳密、access token、Cookie、API key 與 OAuth refresh token。
- 已打包的 `dist/` 與 Swift 的 `.build/` 產物。

App 以 `AIQUOTA_ENDPOINT` 環境變數或本機 `UserDefaults` 的 `quotaEndpoint` 設定資料端點；缺少設定時會顯示明確錯誤，而不是將私有位址寫進原始碼。`.gitignore` 只會防止新的未追蹤檔案被加入，無法清除既有 commit，所以首次推送前必須建立不含舊 commit 的乾淨發布歷史。

---

## 其他實作決策

### 重新整理與動畫

App 啟動、每 300 秒、或使用者按下按鈕時讀取 JSON。`isRefreshing` 防止重複請求；資料不論成功或失敗，loading 至少顯示 0.3 秒。

初版使用 `repeatForever` 旋轉，結束時可能反向歸零或持續旋轉。現在使用 `TimelineView` 只在 `isRefreshing == true` 時計算旋轉角度，因此收到回應後會立即停下。

### JSON 缺值與資料狀態

真實格式可能含有 `five_hour: null` 或 `seven_day: null`。UI 對這些情況顯示 `—`，重置時間沒有值時留空。這避免將「來源沒有提供額度」錯誤表示成「剩餘 0%」。

### 版面與可讀性

面板目前固定 300 pt 寬、內容高度依 SwiftUI fitting size 決定，不出現捲軸。這適合快速查看，但重置時間使用固定欄寬；若未來加入更多 Provider 或較長本地化字串，應考慮改成每一個額度兩行的自適應版面。

## 已完成驗證與尚未完成項目

已完成：

- `swift build`。
- `swift build -c release`。
- App bundle `Info.plist` 格式驗證。
- ZIP 結構驗證。
- 實機檢查選單列、右鍵選單、無資料額度列與重新整理動畫。

尚待補強：

- 為 JSON decoding、缺少 5h／7d、日期格式、HTTP 失敗建立單元測試。
- 建立多螢幕、全螢幕 App、睡眠喚醒與斷網的手動驗收清單。
- 正式發布前導入 Developer ID 簽署與 Apple notarization。
- 若要支援 Intel Mac，建立 Universal Binary；檔案大小會增加。


---

## 5. 重置時間格式與缺值修正

### 問題

原先直接使用 SwiftUI 的系統日期格式，會依 macOS 語系顯示成英文月份（例如 `Jul 22 04:50`），也可能在 `resetsAt: null` 時仍顯示「重置」字樣。

### 修正

- 將 `UsageWindow.resetsAt` 定義為 `Date?`，保留來源的 `null` 語意。
- UI 只有在有重置時間時才顯示「重置」。
- 使用 POSIX locale 與 Gregorian calendar，固定格式為 `MM/dd HH:mm`，例如 `07/22 04:50`。

固定格式避免使用者的系統語系改變欄位寬度與內容，也符合額度面板的既定顯示規格；代價是它不會跟隨本地化日期習慣，若未來支援多語系應改成依 locale 的格式策略。
