## ADDED Requirements

### Requirement: LINE Broadcast Notification
システムは、LINE Messaging APIのブロードキャスト機能を使用して友だち全員に通知を送信しなければならない（SHALL）。個別のuser_idは不要とする。

#### Scenario: Send notification for relevant article
- **WHEN** 関心領域に該当する記事が検出される
- **THEN** LINE公式アカウントの友だち全員にブロードキャスト送信される
- **AND** 通知送信日時がDBに記録される

#### Scenario: Skip notification for irrelevant article
- **WHEN** 関心領域に該当しない記事が処理される
- **THEN** LINE通知は送信されない

### Requirement: Broadcast Batch Limit
システムは、LINE Messaging APIの1回あたり最大5メッセージ制限に従い、バッチ分割送信しなければならない（SHALL）。

#### Scenario: Batch send within limit
- **WHEN** 関心領域該当記事が3件ある
- **THEN** 1回のbroadcast APIコールで3メッセージが送信される

#### Scenario: Batch send exceeding limit
- **WHEN** 関心領域該当記事が8件ある
- **THEN** 5件と3件の2回に分けてbroadcast送信される
- **AND** バッチ間に0.5秒の待機が入る（レートリミット対策）

### Requirement: Notification Message Format
システムは、規定のフォーマットで通知メッセージを構成しなければならない（SHALL）。

#### Scenario: Format notification message
- **WHEN** 金融庁の暗号資産関連記事の通知を作成する
- **THEN** 以下の形式でメッセージが構成される
  ```
  📋 【金融庁】暗号資産
  ━━━━━━━━━━━━━━━━━━━
  {記事タイトル}

  ■ 何が変わる
  {概要}

  ■ 誰に影響
  {対象者}

  ■ いつから
  {施行日}

  ■ 必要な対応
  {アクション}

  🔗 {記事URL}
  📅 {公開日}
  ```

#### Scenario: Truncate long message
- **WHEN** 通知メッセージが5000文字を超える
- **THEN** 4990文字で切り詰め、末尾に「...」を付与する

#### Scenario: Handle missing impact analysis fields
- **WHEN** 影響分析の一部項目が未取得の場合
- **THEN** 該当項目に「情報なし」と表示する

### Requirement: Quota Management
システムは、LINE Messaging APIのクォータ使用状況を確認できなければならない（SHALL）。

#### Scenario: Check monthly quota usage
- **WHEN** クォータ確認APIが呼び出される
- **THEN** 月間上限と今月の使用数が取得される

### Requirement: Scheduled Execution
システムは、1日2回の定時実行で通知を送信しなければならない（SHALL）。

#### Scenario: Execute at scheduled times
- **WHEN** EventBridgeスケジュールが発火する（9:00 JST / 18:00 JST）
- **THEN** Lambda関数が起動される
- **AND** 全監視対象サイトのRSSフィードがチェックされる

#### Scenario: No notification when no new relevant articles
- **WHEN** 定時実行で新規の関心領域該当記事がない
- **THEN** LINE通知は送信されない

### Requirement: Notification Error Handling
システムは、LINE API呼び出しのエラーを適切に処理しなければならない（SHALL）。

#### Scenario: Handle LINE API error
- **WHEN** LINE APIがエラーを返す（認証エラー、レート制限等）
- **THEN** エラーがログに記録される
- **AND** 記事のnotified_atはnullのまま維持される（リトライ対象）

#### Scenario: Handle quota exceeded
- **WHEN** LINE無料枠（200通/月）を超過する
- **THEN** 警告がログに記録される
- **AND** 超過分の通知はスキップされる

### Requirement: Flex Message Support
システムは、将来的にFlex Messageによるリッチ通知に対応できる設計としなければならない（SHALL）。MVP期間中はテキストメッセージを使用する。

#### Scenario: Flex Message in Phase 2
- **WHEN** Phase 2でFlex Messageが有効化される
- **THEN** ヘッダー（情報源・カテゴリ）、本文（影響分析4項目）、フッター（詳細リンクボタン）の構造化されたバブルメッセージが送信される
