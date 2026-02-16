## ADDED Requirements

### Requirement: Interest Domain Definition
システムは、DBのfeed_sourcesテーブルのinterestカラムから情報源ごとの関心領域を取得しなければならない（SHALL）。interestがNULLのソースは全件該当として扱う。

| 情報源 | interest値 | 判定方針 |
|--------|-----------|----------|
| 金融庁 | 暗号資産,仮想通貨,暗号資産交換業,ブロックチェーン,Web3 | キーワード該当時のみ |
| 経済産業省 | 補助金,助成金,支援金,給付金,事業支援 | キーワード該当時のみ |
| 厚生労働省 | 社会保険,健康保険,厚生年金,雇用保険,労災保険,社会保障 | キーワード該当時のみ |
| デジタル庁 | DX,デジタルトランスフォーメーション,マイナンバー,デジタル化 | キーワード該当時のみ |
| 総務省 | NULL | 常に該当（API判定スキップ） |
| e-Gov | NULL | 常に該当（API判定スキップ） |

#### Scenario: Load interest domains from DB
- **WHEN** AI判定処理が開始される
- **THEN** feed_sourcesテーブルからinterestカラムを取得して関心領域マップを構築する
- **AND** interestがNULLのソースはAPI呼び出しをスキップし、常にrelevant=trueとする

### Requirement: Relevance Detection
システムは、Gemini 2.0 Flash APIを使用して記事が関心領域に該当するか判定しなければならない（SHALL）。

#### Scenario: Detect relevant article
- **WHEN** 金融庁の「暗号資産交換業者に対する行政処分について」という記事を判定する
- **THEN** 関心領域「暗号資産」に該当すると判定される
- **AND** is_relevant=true, category="暗号資産" が返される

#### Scenario: Detect irrelevant article
- **WHEN** 金融庁の「幹部人事の発表について」という記事を判定する
- **THEN** 関心領域に該当しないと判定される
- **AND** is_relevant=false が返される

#### Scenario: Always relevant for Soumu and eGov
- **WHEN** 総務省またはe-Govの記事を判定する
- **THEN** 常にis_relevant=trueと判定される
- **AND** categoryは「全般」または「パブリックコメント」が設定される

#### Scenario: Skip summary for irrelevant articles
- **WHEN** 関心領域に該当しないと判定された記事がある
- **THEN** 要約・影響分析のAPI呼び出しはスキップされる
- **AND** APIコストが節約される

### Requirement: Relevance Detection Rules
システムは、見落とし防止を優先した判定ルールに従わなければならない（SHALL）。

#### Scenario: Prioritize avoiding false negatives
- **WHEN** 記事が関心領域に該当するか判断に迷う場合
- **THEN** is_relevant=trueと判定する（見落とし防止優先）

#### Scenario: Batch processing for cost optimization
- **WHEN** 複数の新規記事が検出される
- **THEN** 1回のAPI呼び出しで複数記事をバッチ判定する
- **AND** API呼び出し回数が最小化される

### Requirement: Impact Analysis Generation
システムは、該当記事に対して構造化された影響分析を生成しなければならない（SHALL）。

#### Scenario: Generate impact analysis
- **WHEN** 関心領域に該当する記事の影響分析を生成する
- **THEN** 以下の4項目を含む分析が返される
  - 何が変わる: 規制変更の概要
  - 誰に影響: 影響を受ける主体
  - いつから: 施行日・適用開始日
  - 必要な対応: 具体的に取るべきアクション

#### Scenario: Handle missing information
- **WHEN** 記事内容から施行日が特定できない場合
- **THEN** 「いつから」項目は「未定・要確認」と記載される

### Requirement: API Error Handling
システムは、Gemini API呼び出しのエラーを適切に処理しなければならない（SHALL）。

#### Scenario: Handle API rate limit
- **WHEN** Gemini APIがレート制限エラー（429）を返す
- **THEN** エラーがログに記録される
- **AND** 該当記事はAI処理スキップとしてマークされる

#### Scenario: Handle API timeout
- **WHEN** Gemini API呼び出しが30秒以内に完了しない
- **THEN** タイムアウトエラーとして処理される
- **AND** 該当記事はAI処理スキップとしてマークされる
