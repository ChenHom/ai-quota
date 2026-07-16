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
| 原生玻璃不想帶深色或指定顏色 | 初版用 `.glassEffect(.clear)`；已由第 7 節的 OSD 深色玻璃取代 | 保持系統原生材質、避免額外色彩填滿 | 最終對比受桌布與系統設定影響 |
| 重新整理圖示太快或無法停止 | 最短 0.3 秒 + `TimelineView` | 讓動作可見且能立即停轉 | 載入時會以影格更新角度 |
| 希望三個 Provider 一次看完 | 不使用捲軸，面板依內容高度配置 | 選單列工具應快速掃讀 | 300 pt 寬度使版面較緊湊 |
| 發行檔案大小 | release build 後 `strip -S`，輸出 ZIP | 保留可開啟的 `.app`，同時縮小體積 | 目前未簽署與公證 |
| 清理 Git 歷史後 `dist/` 消失 | 以 `scripts/package.sh` 重新產生 | `dist/` 是可重建產物，不應提交 Git | 每次 clean checkout 後需重新打包 |
| App 顯示網路離線，但 curl 正常 | 宣告本機網路用途並檢查 macOS 權限 | macOS 對 GUI App 有獨立的本機網路隱私控制 | 每個 Bundle ID 都可能需要重新授權 |
| JSON 中 `resetsAt` 為 `null` | 將重置時間改為 Optional | 有額度視窗不代表一定有重置時間 | UI 必須處理空值 |
| 日期顯示成英文月份 | 固定 `MM/dd HH:mm` | 不讓系統語系改變顯示格式 | 不採用使用者所在地的自然語系格式 |
| 面板要貼近原生控制中心的玻璃 | 固定深色玻璃島（OSD 範式）+ 獨立暗化視窗 | 自動深淺適應只對內容稀疏的玻璃生效，資料密集卡片不可依賴 | 亮背景上仍為深色 |
| 玻璃島不會自動深淺適應 | 拆掉 `GlassEffectContainer`、底層不墊任何同視窗圖層 | 玻璃只取樣視窗後方內容，墊底圖層會破壞適應 | 面板輪廓改由第二個視窗提供 |
| `swift run` 讀不到額度網址 | 裸執行檔退回讀取打包版 UserDefaults 網域 | 沒有 bundle ID 時 `standard` 落在不同網域 | 發行 bundle ID 寫死於程式 |

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

## 5. 公開發布後的 release、權限與 JSON 相容性問題

### 5.1 `dist/`／release 目錄消失

#### 現象

建立乾淨的公開 Git 歷史後，原本本機的 `dist/AIQuota.app` 與 ZIP 不見，但 GitHub repository 中也找不到 release 目錄。

#### 原因

`.build/` 與 `dist/` 被列入 `.gitignore`，因為它們是可重新產生的編譯產物，不應進入原始碼 repository。切換到無父歷史的乾淨分支時，這些未追蹤產物不屬於新分支內容，因此不能依賴 Git 保留。

`.gitignore` 的作用是「不追蹤」，不是「備份」或「永久保留本機檔案」。

#### 修正

使用專案的打包腳本重新產生：

```bash
./scripts/package.sh
```

腳本會重新建立：

- `dist/AIQuota.app`
- `dist/AIQuota-macos.zip`

#### 為什麼不把 `dist/` 提交回 Git

二進位會增加 repository 體積，也可能帶入舊端點、舊 Bundle 設定、簽署資訊或不可重現的本機狀態。正式發布若需要保存 binary，應使用 GitHub Releases，而不是提交在 source tree。

### 5.2 公開版移除硬編碼端點後無法連線

#### 現象

公開版移除內網 URL 後，App 顯示「尚未設定額度資料網址」或無法讀取 Collector。

#### 原因

實際內網 URL 不應提交到公開 repository，因此 `QuotaStore` 不再包含固定端點。App 改為依序讀取：

1. `AIQUOTA_ENDPOINT` 環境變數。
2. App 專屬 `UserDefaults` 的 `quotaEndpoint`。

從 Finder 或 LaunchServices 開啟的 `.app` 通常不會繼承終端機 shell 的環境變數，因此 release App 應使用 `UserDefaults` 設定。

#### 修正

```bash
defaults write com.example.aiquota quotaEndpoint -string "https://quota.example.invalid/quota.json"
```

這筆設定只保存在本機偏好設定，不會進入 Git 或 GitHub。

### 5.3 顯示 `The Internet connection appears to be offline`

#### 診斷過程

檢查結果呈現一個重要差異：

- 不使用 `--insecure` 的 curl 可正常取得 JSON。
- 獨立 Foundation URLSession 測試得到 HTTP 200。
- App 的系統網路日誌卻顯示 `Local network prohibited`，並回傳 `NSURLError -1009`。

因此問題不是 Wi-Fi 真的離線、TLS 憑證失敗或 Collector 無回應，而是 macOS 對 GUI App 的本機網路隱私限制。

#### 修正

在 App bundle 的 `Info.plist` 加入：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>AIQuota needs local network access to retrieve usage data from your configured quota service.</string>
```

使用者可在以下位置檢查：

```text
系統設定 → 隱私權與安全性 → 本機網路 → AIQuota
```

權限開啟並重新啟動新版 bundle 後，系統日誌確認 TLS 驗證成功、HTTP 200 且 request finished successfully。

#### 為什麼 curl 成功不能證明 App 權限正常

Terminal／curl 與獨立 App 是不同執行主體。macOS 會依 App 的 Bundle ID、用途宣告與 TCC 權限判斷是否允許本機網路，所以終端機可連線不代表另一個 GUI App 一定可連線。

### 5.4 顯示 `The data couldn’t be read because it is missing`

#### 現象

加入本機網路權限後，錯誤從 offline 變成資料缺失。這個變化表示網路層已成功，失敗點移到 JSON decoding。

即時 JSON 中出現以下有效資料：

```json
{
  "remainingPercent": 100,
  "resetsAt": null
}
```

原本 `UsageWindow.resetsAt` 被定義為非 Optional `Date`，所以 JSONDecoder 遇到 `null` 會拋出 `valueNotFound`。

#### 修正

將模型改為：

```swift
let resetsAt: Date?
```

UI 只有在日期存在時才顯示「重置 MM/dd HH:mm」；日期為 `null` 時整段留空。這符合既有產品規則：沒有重置時間時，不應只顯示「重置」或破折號。

### 5.5 靜態 JSON 回傳 `304` 與快取

系統日誌曾顯示手動重新整理收到 HTTP 304。對每五分鐘更新的 quota JSON，App 應明確要求最新內容，避免 URLSession 的 validator／cache 狀態影響重新整理結果。

修正方式：

- `URLRequest.cachePolicy = .reloadIgnoringLocalCacheData`
- 加入 `Cache-Control: no-cache`
- 設定 15 秒 request timeout

這不代表伺服器完全不能使用快取，而是每次 App 主動重新整理時都應完成重新驗證並取得可解碼內容。

### 5.6 重置日期變成英文月份

#### 現象

使用 Swift `Date.formatted` 時，系統語系可能把日期顯示為 `Jul 22 at 04:58`。需求則是固定的純數字格式。

#### 修正

使用固定 DateFormatter：

```swift
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.calendar = Calendar(identifier: .gregorian)
formatter.dateFormat = "MM/dd HH:mm"
```

最終顯示：

```text
重置 07/22 04:50
```

`en_US_POSIX` 在這裡不是要顯示英文，而是避免使用者語系改寫固定格式；真正的輸出由 `MM/dd HH:mm` 決定。

### 5.7 本次驗證順序

1. 使用正常 TLS 驗證的 curl 取得 JSON。
2. 使用 Foundation URLSession 確認 HTTP 200。
3. 從 macOS unified log 分辨 `Local network prohibited` 與 TLS 錯誤。
4. 加入本機網路用途宣告並重新打包。
5. 比對即時 JSON 與 Swift Decodable 模型。
6. 驗證 `resetsAt: null` 可成功解碼且 UI 不顯示重置文字。
7. 驗證日期固定為 `MM/dd HH:mm`。
8. 執行 debug／release build、`plutil` 與 ZIP 完整性檢查。

---

## 其他實作決策

### 重新整理與動畫

App 啟動、每 300 秒、或使用者按下按鈕時讀取 JSON。`isRefreshing` 防止重複請求；資料不論成功或失敗，loading 至少顯示 0.3 秒。

初版使用 `repeatForever` 旋轉，結束時可能反向歸零或持續旋轉。現在使用 `TimelineView` 只在 `isRefreshing == true` 時計算旋轉角度，因此收到回應後會立即停下。

### JSON 缺值與資料狀態

真實格式可能含有 `five_hour: null`、`seven_day: null`，或額度視窗存在但 `resetsAt: null`。UI 對缺少的額度視窗顯示 `—`，重置時間沒有值時留空。這避免將「來源沒有提供額度」錯誤表示成「剩餘 0%」，也避免 JSONDecoder 因合法的 `null` 值失敗。

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

## 6. 重置時間格式與缺值修正

### 問題

原先直接使用 SwiftUI 的系統日期格式，會依 macOS 語系顯示成英文月份（例如 `Jul 22 04:50`），也可能在 `resetsAt: null` 時仍顯示「重置」字樣。

### 修正

- 將 `UsageWindow.resetsAt` 定義為 `Date?`，保留來源的 `null` 語意。
- UI 只有在有重置時間時才顯示「重置」。
- 使用 POSIX locale 與 Gregorian calendar，固定格式為 `MM/dd HH:mm`，例如 `07/22 04:50`。

固定格式避免使用者的系統語系改變欄位寬度與內容，也符合額度面板的既定顯示規格；代價是它不會跟隨本地化日期習慣，若未來支援多語系應改成依 locale 的格式策略。

---

## 7. Liquid Glass 面板重構：從仿控制中心到 OSD 範式

### 目標

以 macOS 26 控制中心（深色桌布上為深色透明玻璃、白色視窗前自動轉淺）為視覺基準，重做面板。初版的單一 `.glassEffect(.clear)` 大面板 + 卡片白描邊呈現「奶灰霧面 + 線框」，與原生差距大。

### 迭代記錄（各方案與失敗原因）

| 方案 | 結果 |
|---|---|
| `NSVisualEffectView` 當底 + `.regular` 玻璃島 | 只認 NSAppearance 不認背景；使用者為淺色系統 + 深色桌布，呈現「深背景上浮一塊淺灰霜面」 |
| 面板跟隨選單列 `effectiveAppearance` | 選單列外觀由螢幕頂端桌布決定；面板後方是白色視窗時，原生轉淺而我們仍深 |
| 整片 `.glassEffect(.regular)` 當底 | 會自動深淺適應（實測），但霧太重，背景文字透不過來 |
| 整片 `.glassEffect(.clear)` 當底 | 透明度接近原生，但完全不適應——深背景上呈現淺色白霧 |
| 玻璃探針讀 `@Environment(\.colorScheme)` | 適應不反映在 SwiftUI environment，讀不到 |
| 同視窗墊半透明暗化層 / 玻璃底 | 墊底圖層成為玻璃的取樣對象，破壞島的適應；半透明像素疑似以亮底合成 |

### 實驗得出的 Liquid Glass 行為規則（macOS 26，14+ 次控制變因測試）

1. `.regular` 的自動深淺適應**只對內容稀疏的玻璃生效**：短文字、有留白的島會隨背景翻轉；內容橫跨整寬（進度列、多欄位 row）的島永遠維持系統外觀。逐一排除過：亮度、`frame`、`GeometryReader`、空 `Text`、島高度——唯一完美相關的變數是內容覆蓋率。
2. `.clear` 不適應，只跟 NSAppearance；`Glass` 公開 API 僅 `.regular/.clear/.identity` + `.tint()/.interactive()`，`NSGlassEffectView` 僅 `style/tintColor`——沒有模糊量、透明度或適應開關。
3. 適應在「顯示／重繪當下」取樣視窗後方的螢幕內容；之後移動視窗不會重新適應。`GlassEffectContainer` 會把整批玻璃鎖在第一次取樣。
4. 玻璃只取樣「視窗後方」；任何同視窗的墊底圖層都會被當成取樣對象。
5. 強制 `panel.appearance = darkAqua` 可把所有玻璃（含會適應的）釘在深色，整體一致。
6. 控制中心「透明且自適應的底」需要取樣螢幕像素，第三方需要螢幕錄製權限——不可行。

### 最終決策：音量 OSD 範式

原生除了控制中心還有「永遠深色」的玻璃範式（音量／亮度 OSD）。實作：

- macOS 26 強制 `panel.appearance = darkAqua`；pre-26 沿用選單列 `effectiveAppearance` 代理。
- 每張卡為獨立 `.glassEffect(.regular)` 玻璃島，不用 `GlassEffectContainer`；進度列以 `.background(_, in: Capsule())` + mask 繪製，不用 `GeometryReader`。
- 面板底層完全留空；控制中心式的暗化與輪廓由獨立的 `dimPanel`（child window、黑 14%、圓角 26、`ignoresMouseEvents`）墊在玻璃面板後方——因為在另一個視窗，會被玻璃取樣而不破壞行為。
- 效果：深色背景上幾乎等同原生控制中心（縫隙透出清晰內容、島內模糊暈開）；亮背景上為刻意的深色煙燻玻璃，白字始終可讀。

取捨：放棄全自動深淺適應（API 牆），換得任何背景下都協調一致；保留真實背景模糊與透出。

### Debug hooks（視覺驗證用）

- `AIQUOTA_SHOW_PANEL=1`：啟動 0.5 秒後自動展開面板。
- `AIQUOTA_PANEL_XY=x,y`：指定面板位置（Cocoa 座標；在 `orderFront` 前生效，因為玻璃在顯示當下取樣）。
- `AIQUOTA_NODIM=1`：停用暗化視窗。
