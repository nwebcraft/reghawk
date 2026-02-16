#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================================
# 規制・法改正ウォッチャー - RSS取得プロトタイプ
# ============================================================
# 各省庁のRSSフィードを取得・パースし、新着記事を一覧表示する。
# MVP実装の基盤となるプロトタイプ。
#
# 使い方:
#   ruby rss_fetcher_prototype.rb
#
# 依存:
#   Ruby標準ライブラリのみ（外部gem不要）
# ============================================================

require "net/http"
require "uri"
require "rss"
require "json"
require "time"

# ============================================================
# 監視対象サイトの設定
# ============================================================
FEED_SOURCES = [
  {
    key: "fsa",
    name: "金融庁",
    interest: "暗号資産",
    url: "https://www.fsa.go.jp/fsanews.rdf"
  },
  {
    key: "meti",
    name: "経済産業省",
    interest: "補助金",
    url: "https://www.meti.go.jp/ml_index_release_atom.xml"
  },
  {
    key: "mhlw",
    name: "厚生労働省",
    interest: "社会保険",
    url: "https://www.mhlw.go.jp/stf/news.rdf"
  },
  {
    key: "digital",
    name: "デジタル庁",
    interest: "DX関連",
    url: "https://www.digital.go.jp/news/rss.xml"
  },
  {
    key: "soumu",
    name: "総務省",
    interest: nil,
    url: "https://www.soumu.go.jp/menu_kyotsuu/whatsnew/shinchaku_rss.xml"
  },
  {
    key: "egov",
    name: "e-Gov パブコメ",
    interest: nil,
    url: "https://public-comment.e-gov.go.jp/servlet/Public?CLASSNAME=PCM1013_CLS&feedtype=rss"
  },
].freeze

# ============================================================
# RSS取得モジュール
# ============================================================
module RssFetcher
  def self.fetch_feed(url, timeout: 15)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = timeout
    http.read_timeout = timeout

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "RegHawk/0.1 (RSS Reader)"
    request["Accept"] = "application/rss+xml, application/atom+xml, application/xml, text/xml"

    response = http.request(request)

    redirect_count = 0
    while response.is_a?(Net::HTTPRedirection) && redirect_count < 3
      redirect_uri = URI.parse(response["location"])
      redirect_uri = URI.join(uri, redirect_uri) unless redirect_uri.host
      http = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
      http.use_ssl = (redirect_uri.scheme == "https")
      request = Net::HTTP::Get.new(redirect_uri.request_uri)
      request["User-Agent"] = "RegHawk/0.1 (RSS Reader)"
      response = http.request(request)
      redirect_count += 1
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP #{response.code}: #{response.message}"
    end

    response.body
  end

  def self.parse_feed(xml_content)
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
          description: item.description&.strip
        }
      end
    when RSS::Rss
      feed.channel.items.each do |item|
        articles << {
          title: item.title&.strip,
          url: item.link&.strip,
          published_at: item.pubDate || item.date,
          description: item.description&.strip
        }
      end
    when RSS::Atom::Feed
      feed.entries.each do |entry|
        link = entry.links.find { |l| l.rel == "alternate" }&.href || entry.links.first&.href
        articles << {
          title: entry.title&.content&.strip,
          url: link&.strip,
          published_at: entry.published&.content || entry.updated&.content,
          description: entry.summary&.content&.strip || entry.content&.content&.strip
        }
      end
    end

    articles
  end
end

# ============================================================
# メイン処理
# ============================================================
def main
  puts "=" * 70
  puts "  RegHawk - RSS取得プロトタイプ"
  puts "  実行日時: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
  puts "=" * 70
  puts

  results = {}
  errors = {}

  FEED_SOURCES.each do |source|
    print "#{source[:name]} (#{source[:key]}) ... "

    begin
      xml = RssFetcher.fetch_feed(source[:url])
      articles = RssFetcher.parse_feed(xml)
      results[source[:key]] = {
        source: source,
        articles: articles
      }
      puts "OK #{articles.size}件取得"
    rescue => e
      errors[source[:key]] = { source: source, error: e.message }
      puts "NG エラー: #{e.message}"
    end
  end

  puts
  puts "-" * 70

  results.each do |key, data|
    source = data[:source]
    articles = data[:articles]

    puts
    puts "【#{source[:name]}】 関心領域: #{source[:interest] || "全般"}"
    puts "   取得件数: #{articles.size}件"
    puts "   RSS URL: #{source[:url]}"
    puts

    articles.first(5).each_with_index do |article, i|
      pub_date = if article[:published_at]
                   article[:published_at].strftime("%Y-%m-%d") rescue article[:published_at].to_s[0..9]
                 else
                   "日付なし"
                 end
      puts "   #{i + 1}. [#{pub_date}] #{article[:title]}"
      puts "      #{article[:url]}"
      puts
    end

    if articles.size > 5
      puts "   ... 他 #{articles.size - 5}件"
      puts
    end
  end

  unless errors.empty?
    puts
    puts "エラーが発生したソース:"
    errors.each do |key, data|
      puts "   - #{data[:source][:name]}: #{data[:error]}"
    end
  end

  puts
  puts "=" * 70
  total = results.values.sum { |d| d[:articles].size }
  puts "  取得結果サマリー"
  puts "  成功: #{results.size}/#{FEED_SOURCES.size}サイト"
  puts "  エラー: #{errors.size}/#{FEED_SOURCES.size}サイト"
  puts "  合計記事数: #{total}件"
  puts "=" * 70

  output = results.map do |key, data|
    data[:articles].first(3).map do |article|
      {
        source: key,
        source_name: data[:source][:name],
        interest: data[:source][:interest],
        title: article[:title],
        url: article[:url],
        published_at: article[:published_at]&.iso8601 rescue article[:published_at]&.to_s,
      }
    end
  end.flatten

  File.write("rss_output_sample.json", JSON.pretty_generate(output))
  puts
  puts "サンプルJSON出力: rss_output_sample.json (各ソース上位3件)"
end

main
