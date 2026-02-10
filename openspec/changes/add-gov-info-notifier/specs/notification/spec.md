## ADDED Requirements

### Requirement: LINE Push Notification
システムは、LINE Messaging APIを使用してプッシュ通知を送信しなければならない（SHALL）。

#### Scenario: Send notification for relevant article
- **WHEN** 関心領域に該当する記事が検出される
- **THEN** LINE公式アカウントの友だち全員にプッシュ通知が送信される
- **AND** 通知送信日時がDBに記録される

#### Scenario: Skip notification for irrelevant article
- **WHEN** 関心領域に該当しない記事が処理される
- **THEN** LINE通知は送信されない

### Requirement: Notification Message Format
システムは、規定のフォーマットで通知メッセージを構成しなければならない（SHALL）。

#### Scenario: Format notification message
- **WHEN** 金融庁の暗号資産関連記事の通知を作成する
- **THEN** 以下の形式でメッセージが構成される
  ```
  【金融庁】暗号資産関連
  ━━━━━━━━━━━━━━━━━━━
  {記事タイトル}

  ■ 何が変わる：{概要}
  ■ 誰に影響：{対象者}
  ■ いつから：{施行日}
  ■ 必要な対応：{アクション}

  詳細：{記事URL}
  {公開日}
  ```

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
