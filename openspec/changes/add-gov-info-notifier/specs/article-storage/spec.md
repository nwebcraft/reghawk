## ADDED Requirements

### Requirement: Article Persistence
システムは、取得した記事をPostgreSQLデータベースに永続化しなければならない（SHALL）。

#### Scenario: Save new article
- **WHEN** 新規記事（DBに存在しないURL）を保存する
- **THEN** articlesテーブルにレコードが作成される
- **AND** source, title, url, published_at, created_atが記録される

#### Scenario: Save article with AI analysis results
- **WHEN** AI判定・要約が完了した記事を保存する
- **THEN** is_relevant, category, summary, impact_analysisが記録される

#### Scenario: Record notification timestamp
- **WHEN** LINE通知を送信した記事を更新する
- **THEN** notified_atに通知日時が記録される

### Requirement: Duplicate Detection
システムは、URLをキーとして記事の重複を検出しなければならない（SHALL）。

#### Scenario: Detect duplicate article by URL
- **WHEN** 既にDBに存在するURLの記事を処理しようとする
- **THEN** 重複として検出される
- **AND** その記事はスキップされる

#### Scenario: Process new article
- **WHEN** DBに存在しないURLの記事を処理する
- **THEN** 新規記事として処理が継続される

### Requirement: Article Query
システムは、保存された記事を検索・取得できなければならない（SHALL）。

#### Scenario: Query articles by source
- **WHEN** 特定の情報源（例: fsa）の記事を検索する
- **THEN** その情報源の記事のみが返される
- **AND** 公開日時の降順でソートされる

#### Scenario: Query relevant articles only
- **WHEN** 関心領域に該当する記事（is_relevant=true）を検索する
- **THEN** AI判定で該当と判定された記事のみが返される
