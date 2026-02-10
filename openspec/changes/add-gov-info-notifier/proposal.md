# Change: 官公庁情報更新通知システム（RegHawk）の新規構築

## Why

官公庁サイトや業界団体等の情報更新を手動で確認するのは手間がかかり、重要な規制・法改正情報を見落とすリスクがある。RSSフィードを自動取得し、AIによる関心領域判定・要約・影響分析を付けて通知するシステムを構築することで、規制変更の見落としリスクを低減し、情報収集を自動化する。

## What Changes

本提案は新規システムの構築であり、以下の4つの主要機能を実装する。

### 1. RSSフィード取得機能（rss-fetcher）
- 6つの監視対象サイト（金融庁、経済産業省、厚生労働省、デジタル庁、総務省、e-Govパブコメ）からRSSフィードを取得
- RSS 1.0、RSS 2.0、Atomフォーマットの統一的なパース
- リダイレクト対応、タイムアウト処理、エラーハンドリング

### 2. 記事保存・差分検知機能（article-storage）
- Neon PostgreSQLを使用した記事データの永続化
- URLをキーとした重複判定による差分検知
- 記事メタデータ（情報源、公開日時、AI判定結果等）の管理

### 3. AI判定・要約機能（ai-analysis）
- Gemini 2.0 Flash APIを使用した2段階処理
  - Step 1: 関心領域判定（暗号資産、補助金、社会保険、DX関連等）
  - Step 2: 影響分析生成（何が変わる、誰に影響、いつから、必要な対応）
- 非該当記事のスキップによるAPIコスト最適化

### 4. 通知機能（notification）
- LINE Messaging APIによるプッシュ通知
- 構造化された通知フォーマット（カテゴリ、要約、影響分析、リンク）
- 1日2回（9:00/18:00 JST）の定時実行

### インフラ構成
- AWS Lambda (Ruby 3.3) + Amazon EventBridge
- Neon PostgreSQL（無料枠512MB）
- AWS SAMによるデプロイ

## Impact

- Affected specs: なし（新規システム）
- Affected code: 新規作成
  - `lib/rss_fetcher.rb` - RSS取得・パース
  - `lib/article_repository.rb` - 記事DB操作
  - `lib/ai_analyzer.rb` - Gemini API連携
  - `lib/notifier.rb` - LINE通知
  - `lib/handler.rb` - Lambda エントリーポイント
  - `template.yaml` - SAMテンプレート
- 外部依存:
  - Neon PostgreSQL（データベース）
  - Gemini 2.0 Flash API（AI処理）
  - LINE Messaging API（通知）
  - AWS Lambda / EventBridge（実行環境）

## Out of Scope（MVP外）

以下はMVP後のフェーズで対応予定：
- 審議会資料・通達・ガイドラインの監視
- メール通知（SendGrid / Amazon SES）
- Slack / Discord通知
- Webダッシュボード
- ユーザーごとの関心領域カスタマイズ
- 通知頻度・時刻のユーザー設定

## Risks

| リスク | 影響 | 対策 |
|--------|------|------|
| RSS URL変更 | フィード取得不可 | エラー通知設置、定期的な疎通確認 |
| AI判定の誤検知・見落とし | 不要通知または重要情報見落とし | プロンプト調整、精度検証 |
| LINE無料枠超過（200通/月） | 通知送信不可 | フィルタリング精度向上 |
| Neon無料枠超過（512MB） | DB書き込み不可 | 古いデータのアーカイブ |
