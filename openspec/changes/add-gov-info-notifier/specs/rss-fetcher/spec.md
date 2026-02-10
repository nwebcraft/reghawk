## ADDED Requirements

### Requirement: RSS Feed Fetching
システムは、設定された監視対象サイトからRSSフィードをHTTPで取得しなければならない（SHALL）。

#### Scenario: Successful RSS fetch from FSA
- **WHEN** 金融庁のRSSフィードURL（https://www.fsa.go.jp/fsanews.rdf）にアクセスする
- **THEN** HTTPステータス200でRSSコンテンツを取得できる
- **AND** 取得したコンテンツをRSSとしてパースできる

#### Scenario: Handle HTTP redirect
- **WHEN** RSSフィードURLがリダイレクト（301/302）を返す
- **THEN** リダイレクト先URLに自動的にアクセスする（最大3回まで）
- **AND** 最終的なレスポンスを取得する

#### Scenario: Handle network timeout
- **WHEN** RSSフィードへのアクセスが15秒以内に完了しない
- **THEN** タイムアウトエラーとして処理する
- **AND** エラー情報をログに記録する

### Requirement: RSS Format Parsing
システムは、RSS 1.0、RSS 2.0、Atomフォーマットを統一的にパースしなければならない（SHALL）。

#### Scenario: Parse RSS 1.0 (RDF) format
- **WHEN** 厚生労働省のRSSフィード（RSS 1.0形式）を取得する
- **THEN** 記事のタイトル、URL、公開日時、説明を抽出できる

#### Scenario: Parse RSS 2.0 format
- **WHEN** e-GovパブコメのRSSフィード（RSS 2.0形式）を取得する
- **THEN** 記事のタイトル、URL、公開日時、説明を抽出できる

#### Scenario: Parse Atom format
- **WHEN** 経済産業省のAtomフィードを取得する
- **THEN** 記事のタイトル、URL、公開日時、説明を抽出できる

### Requirement: Feed Source Configuration
システムは、6つの監視対象サイトの設定を管理しなければならない（SHALL）。

#### Scenario: Configure all feed sources
- **WHEN** システムを初期化する
- **THEN** 以下の6サイトのフィード設定が読み込まれる
  - 金融庁（fsa）- 関心領域: 暗号資産
  - 経済産業省（meti）- 関心領域: 補助金
  - 厚生労働省（mhlw）- 関心領域: 社会保険
  - デジタル庁（digital）- 関心領域: DX関連
  - 総務省（soumu）- 関心領域: 汎用
  - e-Govパブコメ（egov）- 関心領域: 全件対象
