#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================================
# RSS URL 疎通確認スクリプト
# ============================================================
# 各省庁のRSS URLにアクセスし、RSSとして有効かどうかを確認する。
# プロトタイプ実行前に、まずこちらを実行してURLの正確性を検証する。
#
# 使い方:
#   ruby rss_url_checker.rb
#
# もしURLが無効だった場合の対処法:
#   1. ブラウザで各省庁の「RSS配信について」ページにアクセス
#   2. RSSリンクを右クリック → リンクのURLをコピー
#   3. 本スクリプトおよびプロトタイプのURLを修正
# ============================================================

require "net/http"
require "uri"
require "rss"

FEEDS = {
  "金融庁" => "https://www.fsa.go.jp/fsanews.rdf",
  "経済産業省" => "https://www.meti.go.jp/ml_index_release_atom.xml",
  "厚生労働省" => "https://www.mhlw.go.jp/stf/news.rdf",
  "デジタル庁" => "https://www.digital.go.jp/news/rss.xml",
  "総務省" => "https://www.soumu.go.jp/menu_kyotsuu/whatsnew/shinchaku_rss.xml",
  "e-Gov パブコメ" => "https://public-comment.e-gov.go.jp/servlet/Public?CLASSNAME=PCM1013_CLS&feedtype=rss",
}

# 代替URLの候補（メインURLが無効だった場合に試す）
ALT_FEEDS = {
  "金融庁" => [
    "https://www.fsa.go.jp/news/news_rss.rdf",
    "https://www.fsa.go.jp/common/whatsnew/shinchaku_rss.xml",
  ],
  "厚生労働省" => [
    "https://www.mhlw.go.jp/stf/kinkyu.rdf",
    "https://www.mhlw.go.jp/stf/houdou.rdf",
  ],
  "デジタル庁" => [
    "https://www.digital.go.jp/rss.xml",
    "https://www.digital.go.jp/feed",
  ],
  "総務省" => [
    "https://www.soumu.go.jp/menu_news/s-news/shinchaku_rss.xml",
    "https://www.soumu.go.jp/main_content/shinchaku_rss.xml",
  ],
  "e-Gov パブコメ" => [
    "https://public-comment.e-gov.go.jp/pcm/rss",
  ],
}

def check_url(name, url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http.open_timeout = 10
  http.read_timeout = 10

  request = Net::HTTP::Get.new(uri.request_uri)
  request["User-Agent"] = "RegHawk/0.1 (RSS URL Checker)"

  response = http.request(request)

  # リダイレクト追跡
  redirect_count = 0
  while response.is_a?(Net::HTTPRedirection) && redirect_count < 3
    new_url = response["location"]
    redirect_uri = URI.parse(new_url)
    redirect_uri = URI.join(uri, redirect_uri) unless redirect_uri.host
    http = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
    http.use_ssl = (redirect_uri.scheme == "https")
    request = Net::HTTP::Get.new(redirect_uri.request_uri)
    request["User-Agent"] = "RegHawk/0.1 (RSS URL Checker)"
    response = http.request(request)
    redirect_count += 1
  end

  unless response.is_a?(Net::HTTPSuccess)
    return { status: :http_error, code: response.code, message: response.message }
  end

  body = response.body
  content_type = response["content-type"] || ""

  # RSSとしてパースできるか
  begin
    feed = RSS::Parser.parse(body, false)
    if feed
      count = case feed
              when RSS::RDF then feed.items.size
              when RSS::Rss then feed.channel.items.size
              when RSS::Atom::Feed then feed.entries.size
              else 0
              end
      feed_type = feed.class.name.split("::").last
      { status: :ok, feed_type: feed_type, item_count: count, content_type: content_type }
    else
      { status: :parse_error, message: "RSSとしてパースできませんでした", content_type: content_type }
    end
  rescue => e
    { status: :parse_error, message: e.message, content_type: content_type }
  end
rescue => e
  { status: :network_error, message: e.message }
end

def main
  puts "=" * 60
  puts "  RSS URL 疎通確認"
  puts "  #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
  puts "=" * 60
  puts

  FEEDS.each do |name, url|
    print "#{name} ... "
    result = check_url(name, url)

    case result[:status]
    when :ok
      puts "OK (#{result[:feed_type]}, #{result[:item_count]}件)"
    when :http_error
      puts "NG HTTP #{result[:code]} #{result[:message]}"

      # 代替URLを試行
      if ALT_FEEDS[name]
        ALT_FEEDS[name].each do |alt_url|
          print "   -> 代替URL試行: #{alt_url} ... "
          alt_result = check_url(name, alt_url)
          if alt_result[:status] == :ok
            puts "OK! このURLを使ってください"
            break
          else
            puts "NG"
          end
        end
      end
    when :parse_error
      puts "パースエラー: #{result[:message]}"
      puts "   Content-Type: #{result[:content_type]}"
    when :network_error
      puts "ネットワークエラー: #{result[:message]}"
    end
  end

  puts
  puts "=" * 60
  puts "  NGのURLがある場合:"
  puts "  1. ブラウザで各省庁の「RSS配信」ページにアクセス"
  puts "  2. RSSリンクのURLをコピー"
  puts "  3. feed_sourcesテーブルまたはrss_url_checker.rbのURLを修正"
  puts "=" * 60
end

main
