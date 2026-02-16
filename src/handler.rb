# frozen_string_literal: true

# ============================================================
# RegHawk - Lambda ハンドラー
# ============================================================
# メインパイプライン:
#   1. DBからフィードソース一覧を取得
#   2. 各ソースのRSSを取得・パース
#   3. 新規記事をDBに保存（URLで重複排除）
#   4. 新規記事をAI判定（関心領域フィルタ）
#   5. 該当記事をAI要約（影響分析生成）
#   6. LINE通知送信
# ============================================================

require_relative "lib/rss_fetcher"
require_relative "lib/ai_analyzer"
require_relative "lib/line_notifier"
require_relative "lib/database"

def lambda_handler(event:, context:)
  puts "RegHawk - 実行開始 #{Time.now}"

  db = RegHawk::Database.new

  begin
    # ============================================================
    # Step 1: フィードソース取得
    # ============================================================
    sources = db.active_feed_sources
    puts "監視対象: #{sources.size}サイト"

    # ============================================================
    # Step 2: RSS取得 & 新規記事抽出
    # ============================================================
    new_articles = []

    sources.each do |source|
      print "  #{source["name"]} ... "
      begin
        articles = RegHawk::RssFetcher.fetch_and_parse(source["rss_url"])
        saved = db.save_new_articles(articles, source)
        new_articles.concat(saved)
        puts "#{articles.size}件取得, #{saved.size}件新規"
      rescue => e
        puts "エラー: #{e.message}"
      end

      db.update_last_fetched(source["key"])
    end

    puts "新規記事合計: #{new_articles.size}件"

    if new_articles.empty?
      puts "新規記事なし。終了。"
      return { statusCode: 200, body: "No new articles" }
    end

    # ============================================================
    # Step 3: AI判定（関心領域フィルタ）
    # ============================================================
    puts "AI判定開始..."
    judgments = RegHawk::AiAnalyzer.judge_relevance(new_articles, sources)

    relevant_articles = []
    judgments.each_with_index do |judgment, i|
      article = new_articles[i]
      db.update_judgment(article["id"], judgment)

      if judgment["relevant"]
        article.merge!(judgment)
        relevant_articles << article
      end
    end

    puts "該当記事: #{relevant_articles.size}/#{new_articles.size}件"

    if relevant_articles.empty?
      puts "該当記事なし。終了。"
      return { statusCode: 200, body: "No relevant articles" }
    end

    # ============================================================
    # Step 4: AI要約・影響分析（該当記事のみ）
    # ============================================================
    puts "AI要約開始..."
    relevant_articles.each do |article|
      begin
        # 詳細ページの内容を取得
        content = RegHawk::RssFetcher.fetch_page_content(article["url"])
        analysis = RegHawk::AiAnalyzer.analyze_impact(
          article["source_name"], article["title"], content
        )
        db.update_analysis(article["id"], analysis)
        article.merge!(analysis)
      rescue => e
        puts "  要約エラー (#{article["title"][0..30]}...): #{e.message}"
      end
    end

    # ============================================================
    # Step 5: LINE通知
    # ============================================================
    puts "LINE通知送信..."

    articles_to_notify = relevant_articles.select { |a| a["what_changes"] }

    if articles_to_notify.any?
      RegHawk::LineNotifier.notify_articles(articles_to_notify)
      articles_to_notify.each { |a| db.mark_notified(a["id"]) }
    end

    puts "RegHawk - 実行完了"
    puts "  新規: #{new_articles.size}, 該当: #{relevant_articles.size}, 通知: #{articles_to_notify.size}"

    {
      statusCode: 200,
      body: JSON.generate({
        new_articles: new_articles.size,
        relevant: relevant_articles.size,
        notified: articles_to_notify.size
      })
    }

  ensure
    db.close
  end

rescue => e
  puts "致命的エラー: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  { statusCode: 500, body: e.message }
end
