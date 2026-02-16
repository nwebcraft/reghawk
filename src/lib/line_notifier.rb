# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module RegHawk
  module LineNotifier
    API_BASE = "https://api.line.me/v2/bot"

    def self.notify_articles(articles)
      return if articles.empty?

      articles.each_slice(5) do |batch|
        messages = batch.map { |a| build_text_message(a) }
        broadcast(messages)
        sleep(0.5)
      end
    end

    def self.broadcast(messages)
      uri = URI.parse("#{API_BASE}/message/broadcast")
      token = ENV.fetch("REGHAWK_LINE_CHANNEL_TOKEN")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{token}"
      request.body = JSON.generate({ messages: messages })

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        puts "  LINE送信失敗: #{response.code} - #{response.body}"
      end
    end

    def self.build_text_message(article)
      # Hash のキーが文字列・シンボル両対応
      get = ->(key) { article[key] || article[key.to_s] }

      source_name = get.call(:source_name) || "不明"
      category    = get.call(:category)    || "全般"
      title       = get.call(:title)       || "タイトルなし"
      url         = get.call(:url)         || ""
      pub_date    = get.call(:published_at) || ""
      what        = get.call(:what_changes)    || "情報なし"
      who         = get.call(:who_affected)    || "情報なし"
      when_       = get.call(:effective_date)  || get.call(:when) || "情報なし"
      action      = get.call(:action_required) || "情報なし"

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
  end
end
