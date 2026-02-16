# frozen_string_literal: true

require "net/http"
require "uri"
require "rss"

module RegHawk
  module RssFetcher
    USER_AGENT = "RegHawk/0.1 (RSS Reader)"

    # RSSフィードを取得してパースし、記事一覧を返す
    def self.fetch_and_parse(rss_url, timeout: 15)
      xml = fetch(rss_url, timeout: timeout)
      parse(xml)
    end

    # URLからHTMLコンテンツを取得（AI要約用の詳細ページ取得）
    # テキストのみ抽出（簡易的にタグ除去）
    def self.fetch_page_content(url, timeout: 15, max_chars: 8000)
      body = fetch(url, timeout: timeout)

      # 簡易HTMLタグ除去
      text = body
        .gsub(/<script[^>]*>.*?<\/script>/mi, "")
        .gsub(/<style[^>]*>.*?<\/style>/mi, "")
        .gsub(/<[^>]+>/, " ")
        .gsub(/&nbsp;/, " ")
        .gsub(/&amp;/, "&")
        .gsub(/&lt;/, "<")
        .gsub(/&gt;/, ">")
        .gsub(/\s+/, " ")
        .strip

      # トークン節約のためmax_charsで切り詰め
      text.length > max_chars ? text[0, max_chars] + "..." : text
    end

    private

    def self.fetch(url, timeout: 15)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "application/rss+xml, application/atom+xml, application/xml, text/xml, text/html"

      response = http.request(request)

      # リダイレクト対応
      redirect_count = 0
      while response.is_a?(Net::HTTPRedirection) && redirect_count < 3
        redirect_uri = URI.parse(response["location"])
        redirect_uri = URI.join(uri, redirect_uri) unless redirect_uri.host
        http = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
        http.use_ssl = (redirect_uri.scheme == "https")
        request = Net::HTTP::Get.new(redirect_uri.request_uri)
        request["User-Agent"] = USER_AGENT
        response = http.request(request)
        redirect_count += 1
      end

      raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def self.parse(xml_content)
      feed = RSS::Parser.parse(xml_content, false)
      return [] unless feed

      articles = []

      case feed
      when RSS::RDF
        feed.items.each do |item|
          articles << {
            title: item.title&.strip,
            url: item.link&.strip,
            published_at: item.dc_date || item.date,
          }
        end
      when RSS::Rss
        feed.channel.items.each do |item|
          articles << {
            title: item.title&.strip,
            url: item.link&.strip,
            published_at: item.pubDate || item.date,
          }
        end
      when RSS::Atom::Feed
        feed.entries.each do |entry|
          link = entry.links.find { |l| l.rel == "alternate" }&.href || entry.links.first&.href
          articles << {
            title: entry.title&.content&.strip,
            url: link&.strip,
            published_at: entry.published&.content || entry.updated&.content,
          }
        end
      end

      articles
    end
  end
end
