# 公開快照 `/quota.json` schema v2 變更說明

對象：所有透過 HTTP 讀取 `/quota.json` 的外部消費端（例如 macOS AIQuota / AIQuotaWidget）。
生效時間：2026-09-16 10:51 (+08:00) 起，伺服器只輸出 v2；v1 不再提供。

## 一句話

`providers.codex` / `providers.claude` / `providers.agy` 從**單一物件**變成**物件陣列**（一個帳號一個元素），
每個元素多一個 `account` 欄位；`schemaVersion` 從 `1` 變 `2`。元素內其他欄位完全不變。

## 變更對照

| 位置 | v1 | v2 |
|---|---|---|
| `schemaVersion` | `1` | `2` |
| `generatedAt` | ISO 8601 字串 | 不變 |
| `providers.codex` | `ProviderSnapshot` 物件 | `ProviderSnapshot[]`，至少 1 個元素 |
| `providers.claude` | `ProviderSnapshot` 物件 | `ProviderSnapshot[]`，至少 1 個元素（目前 2 個：`main`、`work`） |
| `providers.agy` | `ProviderSnapshot` 物件，**可能缺席** | `ProviderSnapshot[]`，**仍可能缺席** |
| `ProviderSnapshot.account` | 不存在 | **新增**，非空字串，同 provider 內唯一。預設帳號固定叫 `main` |
| `ProviderSnapshot` 其他欄位 | — | 不變（見下表） |

### `ProviderSnapshot` 元素欄位（v2，與 v1 相同的部分）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `provider` | `"codex" \| "claude" \| "agy"` | 與所屬陣列的鍵相同 |
| `account` | `string` | **v2 新增**。帳號標籤 |
| `status` | `"ok" \| "stale" \| "auth_failed" \| "rate_limited" \| "unavailable"` | |
| `confidence` | `"experimental"` | |
| `source` | `string` | 上游端點 |
| `lastSuccessAt` | `string \| null` | ISO 8601 |
| `windows.five_hour` | `{ usedPercent, remainingPercent, resetsAt }` 或 `null` | `resetsAt` 為 ISO 8601 或 `null` |
| `windows.seven_day` | 同上 | agy 恆為 `null` |
| `resetCredits` | 物件或 `null` | 只有 codex 有值 |

陣列內元素順序 = 伺服器設定順序，`main` 永遠在最前。**請用 `account` 比對，不要依賴索引**。

## 範例

v1（舊）：
```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-09-16T02:00:00.000Z",
  "providers": {
    "codex":  { "provider": "codex",  "status": "ok", "windows": { "...": "..." }, "resetCredits": { "...": "..." } },
    "claude": { "provider": "claude", "status": "ok", "windows": { "...": "..." }, "resetCredits": null },
    "agy":    { "provider": "agy",    "status": "ok", "windows": { "...": "..." }, "resetCredits": null }
  }
}
```

v2（新）：
```json
{
  "schemaVersion": 2,
  "generatedAt": "2026-09-16T02:56:34.538Z",
  "providers": {
    "codex": [
      { "provider": "codex", "account": "main", "status": "ok", "confidence": "experimental",
        "source": "chatgpt.com/backend-api/wham/usage", "lastSuccessAt": "2026-09-16T02:56:34.538Z",
        "windows": {
          "five_hour": { "usedPercent": 0,   "remainingPercent": 100, "resetsAt": "2026-09-16T07:30:11.000Z" },
          "seven_day": { "usedPercent": 100, "remainingPercent": 0,   "resetsAt": "2026-09-19T12:03:09.000Z" }
        },
        "resetCredits": { "availableCount": 2, "applicableAvailableCount": 2,
          "credits": [ { "status": "available", "grantedAt": "2026-09-04T01:39:45.503Z", "expiresAt": "2026-10-04T01:39:45.503Z" } ] } }
    ],
    "claude": [
      { "provider": "claude", "account": "main", "status": "ok", "confidence": "experimental",
        "source": "api.anthropic.com/api/oauth/usage", "lastSuccessAt": "2026-09-16T02:56:34.538Z",
        "windows": {
          "five_hour": { "usedPercent": 39, "remainingPercent": 61, "resetsAt": "2026-09-16T04:10:00.894Z" },
          "seven_day": { "usedPercent": 5,  "remainingPercent": 95, "resetsAt": "2026-09-22T23:00:00.894Z" }
        },
        "resetCredits": null },
      { "provider": "claude", "account": "work", "status": "ok", "confidence": "experimental",
        "source": "api.anthropic.com/api/oauth/usage", "lastSuccessAt": "2026-09-16T02:56:34.538Z",
        "windows": {
          "five_hour": { "usedPercent": 5, "remainingPercent": 95, "resetsAt": "2026-09-16T07:00:00.478Z" },
          "seven_day": { "usedPercent": 1, "remainingPercent": 99, "resetsAt": "2026-09-17T04:00:00.478Z" }
        },
        "resetCredits": null }
    ],
    "agy": [
      { "provider": "agy", "account": "main", "status": "ok", "confidence": "experimental",
        "source": "daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels#model=gemini-3.6-flash-high",
        "lastSuccessAt": "2026-09-16T02:56:34.538Z",
        "windows": {
          "five_hour": { "usedPercent": 0, "remainingPercent": 100, "resetsAt": "2026-09-16T07:56:35.000Z" },
          "seven_day": null
        },
        "resetCredits": null }
    ]
  }
}
```

## 消費端要改的事

1. `schemaVersion` 判斷改成 `== 2`（不等於就視為不可用，跟以前對 `1` 的處理一樣）。
2. 三個 provider 的解碼型別由單一物件改為陣列；`agy` 仍是 optional。
3. 元素型別加上 `account: String`。
4. 顯示：每個元素一列；`account == "main"` 沿用原本的 provider 名稱，其他帳號加上標籤（建議 `Claude (work)`）。
5. 「只想維持舊行為」的最小改法：每個 provider 取 `[0]`（一定是 `main`），其他邏輯不動——但這樣看不到第二個 Claude 帳號。

Swift `Codable` 示意：
```swift
struct Snapshot: Decodable {
    let schemaVersion: Int          // 必須是 2
    let generatedAt: String
    let providers: Providers
}
struct Providers: Decodable {
    let codex: [ProviderSnapshot]
    let claude: [ProviderSnapshot]
    let agy: [ProviderSnapshot]?     // 仍可能缺席
}
struct ProviderSnapshot: Decodable {
    let provider: String
    let account: String              // v2 新增
    let status: String
    let confidence: String
    let source: String
    let lastSuccessAt: String?
    let windows: Windows
    let resetCredits: ResetCredits?  // 只有 codex 非 nil
}
```

## 未來擴充

之後 codex / agy 也可能出現第二個帳號，形狀完全相同（陣列多一個元素、`account` 不同），消費端不需再改 schema。
