#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================================
# RegHawk - DBスキーマ & マイグレーション
# ============================================================
# Neon PostgreSQL 用のスキーマ定義。
#
# 使い方:
#   1. Neonでプロジェクト作成 → 接続文字列を取得
#   2. 環境変数に設定:
#      export REGHAWK_DATABASE_URL="postgres://user:pass@ep-xxx.region.neon.tech/reghawk"
#   3. マイグレーション実行:
#      ruby db_migrate.rb
#
# 依存:
#   gem install pg
# ============================================================

require "pg"

DATABASE_URL = ENV.fetch("REGHAWK_DATABASE_URL") do
  abort <<~MSG
    環境変数 REGHAWK_DATABASE_URL が設定されていません。

    Neonのダッシュボードから接続文字列を取得し、以下のように設定してください:
      export REGHAWK_DATABASE_URL="postgres://user:pass@ep-xxx.region.neon.tech/reghawk?sslmode=require"
  MSG
end

# ============================================================
# スキーマ定義
# ============================================================
MIGRATIONS = [
  {
    version: 1,
    name: "create_articles",
    sql: <<~SQL
      CREATE TABLE IF NOT EXISTS articles (
        id              SERIAL PRIMARY KEY,

        -- 情報源
        source          VARCHAR(20)   NOT NULL,  -- fsa, meti, mhlw, digital, soumu, egov
        source_name     VARCHAR(50)   NOT NULL,  -- 金融庁, 経済産業省, etc.

        -- 記事情報
        title           TEXT          NOT NULL,
        url             TEXT          NOT NULL,
        published_at    TIMESTAMP,

        -- AI判定結果
        is_relevant     BOOLEAN,                 -- 関心領域に該当するか
        category        VARCHAR(100),            -- 暗号資産, 補助金, 社会保険, etc.

        -- AI要約・影響分析
        summary         TEXT,
        what_changes    TEXT,                    -- 何が変わる
        who_affected    TEXT,                    -- 誰に影響
        effective_date  TEXT,                    -- いつから
        action_required TEXT,                    -- 必要な対応

        -- 通知管理
        notified_at     TIMESTAMP,               -- 通知送信日時（NULLなら未通知）

        -- メタ
        created_at      TIMESTAMP    NOT NULL DEFAULT NOW(),
        updated_at      TIMESTAMP    NOT NULL DEFAULT NOW(),

        -- 重複防止（同じURLは2回登録しない）
        CONSTRAINT uq_articles_url UNIQUE (url)
      );

      -- インデックス
      CREATE INDEX IF NOT EXISTS idx_articles_source
        ON articles (source);
      CREATE INDEX IF NOT EXISTS idx_articles_published_at
        ON articles (published_at DESC);
      CREATE INDEX IF NOT EXISTS idx_articles_is_relevant
        ON articles (is_relevant) WHERE is_relevant = true;
      CREATE INDEX IF NOT EXISTS idx_articles_notified_at
        ON articles (notified_at);
      CREATE INDEX IF NOT EXISTS idx_articles_created_at
        ON articles (created_at DESC);
    SQL
  },
  {
    version: 2,
    name: "create_feed_sources",
    sql: <<~SQL
      CREATE TABLE IF NOT EXISTS feed_sources (
        id              SERIAL PRIMARY KEY,
        key             VARCHAR(20)   NOT NULL UNIQUE,  -- fsa, meti, etc.
        name            VARCHAR(50)   NOT NULL,
        rss_url         TEXT          NOT NULL,
        interest        VARCHAR(200),                   -- 関心領域キーワード（NULLは全件対象）
        is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
        last_fetched_at TIMESTAMP,
        created_at      TIMESTAMP     NOT NULL DEFAULT NOW()
      );

      -- 初期データ投入
      INSERT INTO feed_sources (key, name, rss_url, interest) VALUES
        ('fsa',     '金融庁',       'https://www.fsa.go.jp/fsaNewsListAll_rss2.xml',
         '暗号資産,仮想通貨,暗号資産交換業,ブロックチェーン,Web3'),
        ('meti',    '経済産業省',   'https://www.meti.go.jp/ml_index_release_atom.xml',
         '補助金,助成金,支援金,給付金,事業支援'),
        ('mhlw',    '厚生労働省',   'https://www.mhlw.go.jp/stf/news.rdf',
         '社会保険,健康保険,厚生年金,雇用保険,労災保険,社会保障'),
        ('digital', 'デジタル庁',   'https://www.digital.go.jp/rss/news.xml',
         'DX,デジタルトランスフォーメーション,マイナンバー,デジタル化'),
        ('soumu',   '総務省',       'https://www.soumu.go.jp/news.rdf',
         NULL),
        ('egov',    'e-Gov パブコメ', 'https://www.e-gov.go.jp/news/news.xml',
         NULL)
      ON CONFLICT (key) DO NOTHING;
    SQL
  },
  {
    version: 3,
    name: "create_schema_migrations",
    sql: <<~SQL
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version     INTEGER     NOT NULL PRIMARY KEY,
        name        VARCHAR(100) NOT NULL,
        migrated_at TIMESTAMP   NOT NULL DEFAULT NOW()
      );
    SQL
  },
].freeze

# ============================================================
# マイグレーション実行
# ============================================================
def run_migrations
  conn = PG.connect(DATABASE_URL)

  puts "=" * 60
  puts "  RegHawk - DBマイグレーション"
  puts "=" * 60
  puts

  # schema_migrationsテーブルを最初に作成（version 3を先に実行）
  migration_table = MIGRATIONS.find { |m| m[:version] == 3 }
  conn.exec(migration_table[:sql])

  # 適用済みバージョンを取得
  applied = conn.exec("SELECT version FROM schema_migrations ORDER BY version")
                .map { |row| row["version"].to_i }

  MIGRATIONS.each do |migration|
    if applied.include?(migration[:version])
      puts "  v#{migration[:version]} #{migration[:name]} ... スキップ（適用済み）"
      next
    end

    print "  v#{migration[:version]} #{migration[:name]} ... "
    begin
      conn.exec("BEGIN")
      conn.exec(migration[:sql])
      conn.exec_params(
        "INSERT INTO schema_migrations (version, name) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        [migration[:version], migration[:name]]
      )
      conn.exec("COMMIT")
      puts "完了"
    rescue => e
      conn.exec("ROLLBACK")
      puts "エラー: #{e.message}"
      raise
    end
  end

  # 確認
  puts
  puts "-" * 60
  puts "  テーブル一覧:"
  tables = conn.exec(<<~SQL)
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename IN ('articles', 'feed_sources', 'schema_migrations')
    ORDER BY tablename
  SQL
  tables.each { |row| puts "    - #{row["tablename"]}" }

  puts
  puts "  フィードソース:"
  sources = conn.exec("SELECT key, name, interest FROM feed_sources ORDER BY key")
  sources.each do |row|
    interest = row["interest"] || "（全件対象）"
    puts "    - #{row["key"]}: #{row["name"]} [#{interest}]"
  end

  puts
  puts "=" * 60
  puts "  マイグレーション完了"
  puts "=" * 60

  conn.close
end

# ============================================================
# スキーマ削除（開発用リセット）
# ============================================================
def drop_all
  conn = PG.connect(DATABASE_URL)

  puts "全テーブルを削除します。本当に実行しますか？ (yes/no)"
  answer = $stdin.gets&.strip
  unless answer == "yes"
    puts "中止しました。"
    return
  end

  %w[articles feed_sources schema_migrations].each do |table|
    conn.exec("DROP TABLE IF EXISTS #{table} CASCADE")
    puts "  #{table} 削除"
  end

  conn.close
  puts "リセット完了"
end

# ============================================================
# エントリポイント
# ============================================================
if __FILE__ == $0
  case ARGV[0]
  when "migrate", nil
    run_migrations
  when "reset"
    drop_all
  when "schema"
    # スキーマのSQL出力のみ（実行しない）
    MIGRATIONS.each do |m|
      puts "-- v#{m[:version]}: #{m[:name]}"
      puts m[:sql]
      puts
    end
  else
    puts "Usage: ruby db_migrate.rb [migrate|reset|schema]"
  end
end
