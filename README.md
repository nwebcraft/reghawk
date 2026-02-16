# 🦅 RegHawk - 規制・法改正ウォッチャー

官公庁サイトの更新を自動検知し、AIで要約・影響分析してLINE通知するシステム。

## アーキテクチャ

```
EventBridge (cron: 1日2回 9:00/18:00 JST)
    ↓
Lambda (Ruby 3.3)
    ├── RSSフィード取得 (net/http + rss)
    ├── 差分検知 (Neon PostgreSQL)
    ├── AI判定・要約 (Gemini 2.0 Flash)
    └── LINE通知 (Messaging API)
```

## 監視対象

| サイト | 関心領域 |
|--------|---------|
| e-Gov パブコメ | 全般 |
| 金融庁 | 暗号資産 |
| 経済産業省 | 補助金 |
| 厚生労働省 | 社会保険 |
| デジタル庁 | DX関連 |
| 総務省 | 全般 |

## セットアップ

### 1. 外部サービスの準備

**Neon PostgreSQL**
1. https://neon.tech でアカウント作成
2. プロジェクト作成 → 接続文字列をメモ

**LINE Messaging API**
1. https://developers.line.biz でチャネル作成
2. チャネルアクセストークン（長期）を取得
3. QRコードで友だち追加

**Google AI Studio (Gemini)**
1. https://aistudio.google.com でAPIキー取得

### 2. DBマイグレーション

```bash
export REGHAWK_DATABASE_URL="postgres://user:pass@ep-xxx.neon.tech/reghawk?sslmode=require"
gem install pg
ruby db_migrate.rb
```

### 3. RSS URL確認

```bash
ruby rss_url_checker.rb
# ❌のURLがあればrss_fetcher.rbのURLを修正
```

### 4. デプロイ

```bash
cd reghawk/

# SAMビルド
sam build

# デプロイ（初回は--guidedで対話的に設定）
sam deploy --guided
# パラメータ入力:
#   DatabaseUrl: Neonの接続文字列
#   LineChannelToken: LINEのトークン
#   GeminiApiKey: GeminiのAPIキー
```

### 5. 動作確認

```bash
# Lambda手動実行
sam remote invoke RegHawkWatcher

# ログ確認
sam logs --name RegHawkWatcher --tail
```

## ローカルテスト

```bash
# LINE通知テスト
export REGHAWK_LINE_CHANNEL_TOKEN="your_token"
ruby line_notifier.rb test

# RSS取得テスト
ruby rss_fetcher_prototype.rb
```

## プロジェクト構成

```
reghawk/
├── template.yaml          # SAMテンプレート（Lambda + EventBridge）
├── src/
│   ├── handler.rb         # Lambdaエントリポイント
│   ├── Gemfile            # 依存関係
│   └── lib/
│       ├── rss_fetcher.rb # RSS取得・パース
│       ├── ai_analyzer.rb # Gemini API連携（判定 + 要約）
│       ├── line_notifier.rb # LINE通知送信
│       └── database.rb    # PostgreSQL操作
├── db_migrate.rb          # DBマイグレーション
├── rss_url_checker.rb     # RSS URL疎通確認
├── rss_fetcher_prototype.rb # RSS取得プロトタイプ
├── ai_prompts.rb          # プロンプト設計・テスト
└── line_notifier.rb       # LINE通知CLI
```

## 月額コスト

| サービス | 料金 |
|---------|------|
| AWS Lambda + EventBridge | 無料枠内 |
| Neon PostgreSQL | 無料（512MB） |
| Gemini 2.0 Flash | 数十円/月 |
| LINE Messaging API | 無料（200通/月） |
| **合計** | **ほぼ0円** |

## ライセンス

MIT
