# frozen_string_literal: true

require "pg"
require "json"

module RegHawk
  class Database
    def initialize
      @conn = PG.connect(ENV.fetch("REGHAWK_DATABASE_URL"))
    end

    def close
      @conn&.close
    end

    # アクティブなフィードソース一覧
    def active_feed_sources
      @conn.exec(<<~SQL).to_a
        SELECT key, name, rss_url, interest
        FROM feed_sources
        WHERE is_active = TRUE
        ORDER BY key
      SQL
    end

    # 新規記事を保存（URLで重複排除）。保存できた記事を返す。
    def save_new_articles(articles, source)
      saved = []

      articles.each do |article|
        result = @conn.exec_params(<<~SQL, [
          source["key"],
          source["name"],
          article[:title],
          article[:url],
          article[:published_at]&.to_s
        ])
          INSERT INTO articles (source, source_name, title, url, published_at)
          VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT (url) DO NOTHING
          RETURNING id, source, source_name, title, url, published_at
        SQL

        if result.ntuples > 0
          saved << result.first
        end
      end

      saved
    end

    # AI判定結果を更新
    def update_judgment(article_id, judgment)
      @conn.exec_params(<<~SQL, [
        judgment["relevant"],
        judgment["category"],
        article_id
      ])
        UPDATE articles
        SET is_relevant = $1, category = $2, updated_at = NOW()
        WHERE id = $3
      SQL
    end

    # AI要約・影響分析を更新
    def update_analysis(article_id, analysis)
      @conn.exec_params(<<~SQL, [
        analysis["summary"],
        analysis["what_changes"],
        analysis["who_affected"],
        analysis["when"],
        analysis["action_required"],
        article_id
      ])
        UPDATE articles
        SET summary = $1, what_changes = $2, who_affected = $3,
            effective_date = $4, action_required = $5, updated_at = NOW()
        WHERE id = $6
      SQL
    end

    # 通知済みフラグを更新
    def mark_notified(article_id)
      @conn.exec_params(<<~SQL, [article_id])
        UPDATE articles
        SET notified_at = NOW(), updated_at = NOW()
        WHERE id = $1
      SQL
    end

    # 最終取得日時を更新
    def update_last_fetched(source_key)
      @conn.exec_params(<<~SQL, [source_key])
        UPDATE feed_sources
        SET last_fetched_at = NOW()
        WHERE key = $1
      SQL
    end
  end
end
