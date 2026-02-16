# Design: 官公庁情報更新通知システム（RegHawk）

## Context

官公庁の規制・法改正情報を自動収集し、AIで要約・影響分析を付けて通知するMVPシステムを構築する。個人利用を想定し、月額ほぼ無料（0〜100円）で運用可能な構成とする。

### 制約事項
- 月額コスト: 100円以下
- 運用負荷: 最小限（サーバーレス）
- 開発期間: MVP優先（シンプルな実装）

## Goals / Non-Goals

### Goals
- 6つの官公庁サイトからRSSフィードを自動取得
- AIで関心領域に該当する記事を判定・要約
- LINE通知で即時に情報を受け取れる
- 重複通知を防止（差分検知）
- 運用コストを最小限に抑える

### Non-Goals
- Webダッシュボード（MVPでは実装しない）
- 複数ユーザー対応（MVPでは個人利用のみ）
- カスタマイズ可能な関心領域設定
- 審議会資料・通達等の監視

## Decisions

### 1. 実行環境: AWS Lambda + EventBridge

**選定理由:**
- サーバー管理不要
- 月100万リクエストまで無料
- EventBridgeでcron実行が容易

**代替案:**
- GitHub Actions: 無料枠は十分だがDBアクセスが煩雑
- Heroku Scheduler: 無料枠廃止済み

### 2. 言語: Ruby 3.3

**選定理由:**
- 標準ライブラリのみでRSSパース可能（rss gem）
- 要件定義でRubyが指定されている
- Nokogiri不要でLambdaパッケージサイズ削減

**代替案:**
- Python: boto3との相性は良いがRSSライブラリが追加依存
- Node.js: コールドスタートが速いが要件外

### 3. データベース: Neon PostgreSQL

**選定理由:**
- サーバーレスPostgreSQL（コネクション管理不要）
- 512MB無料枠で十分
- 標準SQLで拡張性確保

**代替案:**
- DynamoDB: 無料枠あるがスキーマレスで複雑
- SQLite on S3: シンプルだが並行アクセスに課題

### 4. AI処理: Gemini 2.0 Flash

**選定理由:**
- 入力$0.10/1M tokens、出力$0.40/1M tokens（最安クラス）
- 要約・分類タスクに十分な性能
- 月額数十円で運用可能

**代替案:**
- GPT-4o-mini: 性能は同等だがやや高コスト
- Claude 3 Haiku: 同等コストだがGeminiの方が日本語要約に強い

### 5. 通知: LINE Messaging API

**選定理由:**
- 200通/月無料枠
- プッシュ通知で開封率が高い
- 日本での普及率が高い

**実装詳細:**
- 送信方式: ブロードキャスト（`/message/broadcast`）、個別user_id不要
- API Base URL: `https://api.line.me/v2/bot`
- 環境変数: `REGHAWK_LINE_CHANNEL_TOKEN`（チャネルアクセストークン長期）
- 外部gem不要（Ruby標準ライブラリ `net/http`, `json` のみ）
- 1回のbroadcastで最大5メッセージ、超過時はバッチ分割＋0.5秒待機
- テキストメッセージ上限5000文字、超過時は切り詰め

**代替案:**
- Slack: 無料プランではメッセージ履歴制限あり
- メール: 迷惑メールフォルダリスクあり

### 6. AI処理の2段階設計

**選定理由:**
- Step 1（判定）: タイトルのみで関心領域判定 → 非該当をスキップ
- Step 2（要約）: 該当記事のみ詳細取得・要約生成
- APIコスト最適化（非該当記事は詳細取得・要約しない）

**トレードオフ:**
- タイトルだけでは判定精度が落ちる可能性
- → 誤判定時は手動でフィードバック収集し、プロンプト改善

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    EventBridge (cron)                        │
│                  9:00 / 18:00 JST daily                      │
└─────────────────────┬───────────────────────────────────────┘
                      │ invoke
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    AWS Lambda (Ruby 3.3)                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    Handler                             │   │
│  │  1. Fetch RSS feeds (6 sources)                       │   │
│  │  2. Check duplicates against DB                       │   │
│  │  3. AI relevance check (Gemini Flash)                 │   │
│  │  4. AI summary generation (relevant only)             │   │
│  │  5. Send LINE notifications                           │   │
│  │  6. Save articles to DB                               │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────┬─────────────────┬─────────────────┬──────────────┘
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────┐      ┌──────────┐      ┌──────────┐
    │   Neon   │      │  Gemini  │      │   LINE   │
    │PostgreSQL│      │   API    │      │   API    │
    └──────────┘      └──────────┘      └──────────┘
```

## Data Model

### articles テーブル

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PRIMARY KEY | 一意識別子 |
| source | VARCHAR(20) NOT NULL | 情報源キー（fsa, meti, mhlw, digital, soumu, egov） |
| source_name | VARCHAR(50) NOT NULL | 情報源名（金融庁、経済産業省 等） |
| title | TEXT NOT NULL | 記事タイトル |
| url | TEXT NOT NULL UNIQUE | 元記事URL（重複判定キー） |
| published_at | TIMESTAMP | 公開日時 |
| is_relevant | BOOLEAN | AI判定：関心領域該当フラグ |
| category | VARCHAR(100) | AI判定：カテゴリ名 |
| summary | TEXT | AI生成要約 |
| what_changes | TEXT | 何が変わるか |
| who_affected | TEXT | 誰に影響があるか |
| effective_date | TEXT | いつから |
| action_required | TEXT | 必要な対応 |
| notified_at | TIMESTAMP | 通知送信日時（NULLなら未通知） |
| created_at | TIMESTAMP NOT NULL DEFAULT NOW() | レコード作成日時 |
| updated_at | TIMESTAMP NOT NULL DEFAULT NOW() | レコード更新日時 |

### feed_sources テーブル

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PRIMARY KEY | 一意識別子 |
| key | VARCHAR(20) NOT NULL UNIQUE | 情報源キー（fsa, meti 等） |
| name | VARCHAR(50) NOT NULL | 情報源名 |
| rss_url | TEXT NOT NULL | RSSフィードURL |
| interest | VARCHAR(200) | 関心領域キーワード（NULLは全件対象） |
| is_active | BOOLEAN NOT NULL DEFAULT TRUE | 有効フラグ |
| last_fetched_at | TIMESTAMP | 最終取得日時 |
| created_at | TIMESTAMP NOT NULL DEFAULT NOW() | レコード作成日時 |

#### 初期データ

| key | name | rss_url | interest |
|-----|------|---------|----------|
| fsa | 金融庁 | https://www.fsa.go.jp/fsaNewsListAll_rss2.xml | 暗号資産,仮想通貨,暗号資産交換業,ブロックチェーン,Web3 |
| meti | 経済産業省 | https://www.meti.go.jp/ml_index_release_atom.xml | 補助金,助成金,支援金,給付金,事業支援 |
| mhlw | 厚生労働省 | https://www.mhlw.go.jp/stf/news.rdf | 社会保険,健康保険,厚生年金,雇用保険,労災保険,社会保障 |
| digital | デジタル庁 | https://www.digital.go.jp/rss/news.xml | DX,デジタルトランスフォーメーション,マイナンバー,デジタル化 |
| soumu | 総務省 | https://www.soumu.go.jp/news.rdf | NULL（全件対象） |
| egov | e-Gov パブコメ | https://www.e-gov.go.jp/news/news.xml | NULL（全件対象） |

### schema_migrations テーブル

| Column | Type | Description |
|--------|------|-------------|
| version | INTEGER PRIMARY KEY | マイグレーションバージョン |
| name | VARCHAR(100) NOT NULL | マイグレーション名 |
| migrated_at | TIMESTAMP NOT NULL DEFAULT NOW() | 適用日時 |

### インデックス

```sql
CREATE UNIQUE INDEX idx_articles_url ON articles(url);
CREATE INDEX idx_articles_source ON articles(source);
CREATE INDEX idx_articles_published_at ON articles(published_at DESC);
CREATE INDEX idx_articles_is_relevant ON articles(is_relevant) WHERE is_relevant = true;
CREATE INDEX idx_articles_notified_at ON articles(notified_at);
CREATE INDEX idx_articles_created_at ON articles(created_at DESC);
```

## Module Structure

```
src/
├── handler.rb             # Lambda エントリーポイント（パイプライン制御）
├── Gemfile                # 依存関係（pg gem）
└── lib/
    ├── rss_fetcher.rb     # RSS取得・パース + 詳細ページテキスト抽出
    ├── ai_analyzer.rb     # Gemini API連携（判定 + 要約 + プロンプト定義）
    ├── line_notifier.rb   # LINE通知送信
    └── database.rb        # PostgreSQL操作（記事CRUD + フィードソース管理）
```

### ツールスクリプト（プロジェクトルート）

```
reghawk/
├── db_migrate.rb          # DBマイグレーション（migrate / reset / schema）
├── rss_url_checker.rb     # RSS URL疎通確認
├── rss_fetcher_prototype.rb # RSS取得プロトタイプ（開発用）
├── ai_prompts.rb          # プロンプト設計・テスト（開発用）
└── line_notifier.rb       # LINE通知CLIテスト（test / quota / flex_test）
```

## Environment Variables

| 変数名 | 用途 | 使用箇所 |
|--------|------|---------|
| `REGHAWK_DATABASE_URL` | Neon PostgreSQL接続文字列 | database.rb, db_migrate.rb |
| `REGHAWK_LINE_CHANNEL_TOKEN` | LINEチャネルアクセストークン（長期） | line_notifier.rb |
| `REGHAWK_GEMINI_API_KEY` | Gemini API キー | ai_analyzer.rb |

## AI Prompt Design

### 2段階処理アーキテクチャ

APIコスト最適化のため、AI処理を2段階に分離する。

```
新規記事一覧
    │
    ▼
┌─────────────────────────────────┐
│ Step 1: 関心領域判定            │
│ - 入力: タイトル一覧（バッチ）  │
│ - 出力: relevant/category       │
│ - 処理: 1回のAPI呼び出し        │
└─────────────────────────────────┘
    │
    │ relevant=true のみ
    ▼
┌─────────────────────────────────┐
│ Step 2: 要約・影響分析          │
│ - 入力: 詳細ページ内容          │
│ - 出力: 4項目の影響分析         │
│ - 処理: 記事ごとにAPI呼び出し   │
└─────────────────────────────────┘
```

### Step 1: 関心領域判定

**目的**: タイトルのみで関心領域該当を高速判定（コスト最小化）

**入力形式**:
```
1. [金融庁] 暗号資産交換業者に対する新たなガイドラインの公表について
2. [金融庁] 令和7年3月期における金融再生法開示債権の状況等の公表
3. [経済産業省] 令和7年度補正予算「ものづくり補助金」の公募開始について
...
```

**出力形式** (JSON):
```json
[
  {"index": 1, "relevant": true, "category": "暗号資産"},
  {"index": 2, "relevant": false, "category": null},
  {"index": 3, "relevant": true, "category": "補助金"}
]
```

**判定ルール**:
- 該当する場合: `relevant = true`
- 該当しない場合: `relevant = false`
- 判断に迷う場合: `relevant = true`（見落とし防止優先）
- 総務省・e-Gov: 常に `relevant = true`

### Step 2: 要約・影響分析

**目的**: 該当記事の詳細から構造化された影響分析を生成

**入力**: 記事の詳細ページ内容（テキスト抽出済み）

**出力形式** (JSON):
```json
{
  "what_changes": "何が変わるか（規制変更の概要）",
  "who_affected": "誰に影響があるか（影響を受ける主体）",
  "when": "いつから（施行日・適用開始日）",
  "action_required": "必要な対応（具体的に取るべきアクション）",
  "summary": "3行程度の要約"
}
```

**不明項目の扱い**: 情報が特定できない場合は「情報なし」と記載

### Gemini API設定

```ruby
generationConfig: {
  temperature: 0.1,        # 判定・要約は低温で安定させる
  maxOutputTokens: 2048,
  responseMimeType: "application/json"  # JSON出力を強制
}
```

### コスト試算

| 処理 | 入力トークン/回 | 出力トークン/回 | 1日あたり回数 | 月額コスト |
|------|----------------|----------------|--------------|-----------|
| Step 1 (バッチ判定) | ~500 | ~200 | 2回 | ~$0.01 |
| Step 2 (要約生成) | ~2000 | ~500 | ~10記事 | ~$0.10 |
| **合計** | | | | **~$0.11/月** |

## Risks / Trade-offs

### 1. RSS URL変更リスク
- **リスク**: 官公庁がRSS URLを変更するとフィード取得不可
- **軽減策**: 疎通確認スクリプトを定期実行、エラー時にLINE通知

### 2. AI判定精度
- **リスク**: タイトルのみの判定では見落とし・誤検知の可能性
- **軽減策**: 精度検証を継続し、必要に応じて詳細ページも判定対象に

### 3. LINE無料枠超過
- **リスク**: 200通/月を超えると通知不可
- **軽減策**: フィルタリング精度向上で通知数を1日6通以下に抑制

### 4. Neon無料枠超過
- **リスク**: 512MBを超えるとDB書き込み不可
- **軽減策**: 古い記事（6ヶ月以上）を定期削除するバッチ処理

## Migration Plan

新規システムのため移行は不要。

### デプロイ手順
1. Neon PostgreSQLでDBセットアップ
2. LINE公式アカウント作成・API設定
3. Gemini APIキー取得
4. AWS SAMでLambdaデプロイ
5. EventBridgeスケジュール有効化
6. 動作確認・モニタリング設定

## Open Questions

1. **厚生労働省の利用規約対応**: RSS情報の再配布禁止規定があるが、リンク誘導形式であれば問題ないか？公開サービス化時に再確認が必要。

2. **AI判定の閾値設計**: 関心領域判定の確信度が低い場合、どう扱うか？（通知する / しない / 別枠で通知）

3. **エラー時の通知**: RSS取得エラーやAPI障害時、どのように管理者に通知するか？（CloudWatch Alarm → SNS → メール？）
