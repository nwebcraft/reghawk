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

### Requirement: Page Content Extraction
システムは、AI要約のために記事の詳細ページからテキストコンテンツを抽出しなければならない（SHALL）。

#### Scenario: Extract text from HTML page
- **WHEN** 関心領域に該当する記事の詳細ページURLにアクセスする
- **THEN** HTMLタグ（script, style含む）を除去してテキストのみを抽出する
- **AND** HTMLエンティティ（&amp;, &lt;, &gt;, &nbsp;）をデコードする
- **AND** 連続する空白を単一スペースに正規化する

#### Scenario: Truncate long page content
- **WHEN** 抽出したテキストが8000文字を超える
- **THEN** 8000文字で切り詰め、末尾に「...」を付与する（トークン節約）

### Requirement: Feed Source Configuration
システムは、DBのfeed_sourcesテーブルから有効な監視対象サイトの設定を取得しなければならない（SHALL）。

#### Scenario: Load active feed sources from DB
- **WHEN** システムが実行される
- **THEN** feed_sourcesテーブルからis_active=TRUEのソース一覧を取得する
- **AND** 各ソースのkey, name, rss_url, interestが読み込まれる
