#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================================
# RegHawk - LINE通知CLIツール
# ============================================================
# LINE Messaging API を使って、規制・法改正情報の通知を送信する。
#
# セットアップ手順:
#   1. LINE Developers (https://developers.line.biz/) でアカウント作成
#   2. 「Messaging API」チャネルを作成
#      - プロバイダー名: RegHawk
#      - チャネル名: RegHawk - 規制ウォッチャー
#   3. チャネル設定から以下を取得:
#      - チャネルアクセストークン（長期）
#   4. 環境変数に設定:
#      export REGHAWK_LINE_CHANNEL_TOKEN="your_token_here"
#   5. LINE公式アカウントのQRコードを読み取って友だち追加
#   6. テスト送信:
#      ruby line_notifier.rb test
#
# 依存:
#   Ruby標準ライブラリのみ（外部gem不要）
# ============================================================

require "net/http"
require "uri"
require "json"

module RegHawk
  module LineNotifier
    API_BASE = "https://api.line.me/v2/bot"

    # ============================================================
    # 設定
    # ============================================================
    def self.channel_token
      ENV.fetch("REGHAWK_LINE_CHANNEL_TOKEN") do
        abort <<~MSG
          環境変数 REGHAWK_LINE_CHANNEL_TOKEN が設定されていません。

          LINE Developersのチャネル設定から「チャネルアクセストークン（長期）」を
          取得し、以下のように設定してください:
            export REGHAWK_LINE_CHANNEL_TOKEN="your_token_here"
        MSG
      end
    end

    # ============================================================
    # ブロードキャスト送信（友だち全員に送信）
    # ============================================================
    def self.broadcast(messages)
      uri = URI.parse("#{API_BASE}/message/broadcast")

      body = { messages: messages }

      response = post_request(uri, body)

      case response
      when Net::HTTPSuccess
        puts "  LINE送信成功"
        true
      else
        error = JSON.parse(response.body) rescue { "error" => response.body }
        puts "  LINE送信失敗: #{response.code} - #{error}"
        false
      end
    end

    # ============================================================
    # 記事の通知メッセージを構築して送信
    # ============================================================
    def self.notify_article(article)
      message = build_text_message(article)
      broadcast([message])
    end

    # ============================================================
    # 複数記事をまとめて送信（1記事1メッセージ）
    # ============================================================
    def self.notify_articles(articles)
      return if articles.empty?

      puts "LINE通知送信: #{articles.size}件"

      articles.each_slice(5) do |batch|
        messages = batch.map { |a| build_text_message(a) }
        broadcast(messages)
        sleep(0.5)
      end
    end

    # ============================================================
    # テキストメッセージの構築
    # ============================================================
    def self.build_text_message(article)
      source_name = article[:source_name] || article["source_name"]
      category    = article[:category]    || article["category"] || "全般"
      title       = article[:title]       || article["title"]
      url         = article[:url]         || article["url"]
      pub_date    = article[:published_at] || article["published_at"]

      what     = article[:what_changes]    || article["what_changes"]    || "情報なし"
      who      = article[:who_affected]    || article["who_affected"]    || "情報なし"
      when_    = article[:effective_date]  || article["effective_date"]  || "情報なし"
      action   = article[:action_required] || article["action_required"] || "情報なし"

      text = <<~MSG.strip
        📋 【#{source_name}】#{category}
        ━━━━━━━━━━━━━━━━━━━
        #{title}

        ■ 何が変わる
        #{what}

        ■ 誰に影響
        #{who}

        ■ いつから
        #{when_}

        ■ 必要な対応
        #{action}

        🔗 #{url}
        📅 #{pub_date}
      MSG

      text = text[0, 4990] + "..." if text.length > 5000

      { type: "text", text: text }
    end

    # ============================================================
    # Flex Messageの構築（将来拡張用）
    # ============================================================
    def self.build_flex_message(article)
      source_name = article[:source_name] || article["source_name"]
      category    = article[:category]    || article["category"] || "全般"
      title       = article[:title]       || article["title"]
      url         = article[:url]         || article["url"]

      what   = article[:what_changes]    || article["what_changes"]    || "情報なし"
      who    = article[:who_affected]    || article["who_affected"]    || "情報なし"
      when_  = article[:effective_date]  || article["effective_date"]  || "情報なし"
      action = article[:action_required] || article["action_required"] || "情報なし"

      {
        type: "flex",
        altText: "【#{source_name}】#{title}",
        contents: {
          type: "bubble",
          size: "mega",
          header: {
            type: "box",
            layout: "vertical",
            contents: [
              {
                type: "text",
                text: "📋 #{source_name} | #{category}",
                size: "sm",
                color: "#1B4F72",
                weight: "bold"
              },
              {
                type: "text",
                text: title,
                size: "md",
                weight: "bold",
                wrap: true,
                margin: "sm"
              }
            ],
            paddingAll: "lg",
            backgroundColor: "#D6EAF8"
          },
          body: {
            type: "box",
            layout: "vertical",
            contents: [
              flex_section("何が変わる", what),
              { type: "separator", margin: "md" },
              flex_section("誰に影響", who),
              { type: "separator", margin: "md" },
              flex_section("いつから", when_),
              { type: "separator", margin: "md" },
              flex_section("必要な対応", action),
            ],
            paddingAll: "lg"
          },
          footer: {
            type: "box",
            layout: "vertical",
            contents: [
              {
                type: "button",
                action: { type: "uri", label: "詳細を見る", uri: url },
                style: "primary",
                color: "#2E86C1"
              }
            ],
            paddingAll: "md"
          }
        }
      }
    end

    # ============================================================
    # 残り通知数の確認
    # ============================================================
    def self.get_quota
      uri = URI.parse("#{API_BASE}/message/quota")
      response = get_request(uri)

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        puts "  月間上限: #{data["value"] || "無制限"}"
      end

      uri_consumption = URI.parse("#{API_BASE}/message/quota/consumption")
      response = get_request(uri_consumption)

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        puts "  今月の使用数: #{data["totalUsage"]}"
      end
    end

    # ============================================================
    # プライベートメソッド
    # ============================================================
    private

    def self.post_request(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{channel_token}"
      request.body = JSON.generate(body)

      http.request(request)
    end

    def self.get_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 15

      request = Net::HTTP::Get.new(uri.request_uri)
      request["Authorization"] = "Bearer #{channel_token}"

      http.request(request)
    end

    def self.flex_section(label, value)
      {
        type: "box",
        layout: "vertical",
        contents: [
          {
            type: "text",
            text: "■ #{label}",
            size: "xs",
            color: "#1B4F72",
            weight: "bold"
          },
          {
            type: "text",
            text: value.to_s,
            size: "sm",
            wrap: true,
            margin: "xs"
          }
        ],
        margin: "md"
      }
    end
  end
end

# ============================================================
# CLI エントリポイント
# ============================================================
if __FILE__ == $0
  case ARGV[0]
  when "test"
    puts "=" * 60
    puts "  RegHawk - LINE通知テスト"
    puts "=" * 60
    puts

    sample = {
      source_name: "金融庁",
      category: "暗号資産",
      title: "【テスト】暗号資産交換業者に対する新たなガイドラインの公表について",
      url: "https://www.fsa.go.jp/news/test",
      published_at: Time.now.strftime("%Y-%m-%d"),
      what_changes: "暗号資産交換業者に対し、顧客資産の分別管理要件厳格化を求めるガイドラインが公表された。",
      who_affected: "暗号資産交換業者、関連サービス事業者",
      effective_date: "2026年4月1日",
      action_required: "コールドウォレット保管比率の見直し、第三者監査体制の構築",
    }

    puts "テストメッセージを送信します..."
    puts
    msg = RegHawk::LineNotifier.build_text_message(sample)
    puts msg[:text]
    puts
    puts "-" * 60

    RegHawk::LineNotifier.broadcast([msg])

  when "quota"
    puts "=" * 60
    puts "  RegHawk - LINE通知クォータ確認"
    puts "=" * 60
    puts
    RegHawk::LineNotifier.get_quota

  when "flex_test"
    puts "Flex Messageテストを送信します..."
    sample = {
      source_name: "金融庁",
      category: "暗号資産",
      title: "【テスト】暗号資産交換業者に対する新たなガイドラインの公表について",
      url: "https://www.fsa.go.jp/news/test",
      what_changes: "顧客資産の分別管理要件厳格化",
      who_affected: "暗号資産交換業者",
      effective_date: "2026年4月1日",
      action_required: "体制整備、内部規程の見直し",
    }
    msg = RegHawk::LineNotifier.build_flex_message(sample)
    RegHawk::LineNotifier.broadcast([msg])

  else
    puts "Usage: ruby line_notifier.rb [test|quota|flex_test]"
    puts
    puts "  test      - テストメッセージを送信"
    puts "  quota     - 今月の通知数を確認"
    puts "  flex_test - Flex Messageのテスト送信"
  end
end
