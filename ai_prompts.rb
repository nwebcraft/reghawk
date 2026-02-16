#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================================
# RegHawk - AIプロンプト設計
# ============================================================
# Gemini 2.0 Flash API に送信する2段階プロンプトの定義。
# Step 1: 関心領域判定（タイトルのみ → 軽量）
# Step 2: 要約・影響分析（詳細ページ → 該当記事のみ）
# ============================================================
require "json"
module Prompts
  # ============================================================
  # Step 1: 関心領域判定プロンプト
  # ============================================================
  # 入力: 記事タイトル一覧（バッチ処理でAPI呼び出し回数を削減）
  # 出力: JSON配列（各記事のrelevant判定とcategory）
  #
  # ポイント:
  # - タイトルのみで判定するので入力トークンが少なくコスト最小
  # - 複数記事をバッチで送ることで1回のAPI呼び出しで済む
  # - 迷ったらrelevant=trueにする（見落とし防止優先）
  # ============================================================

  STEP1_SYSTEM = <<~PROMPT
    あなたは日本の規制・法改正動向の分析アシスタントです。
    官公庁の報道発表タイトルを見て、ユーザーの関心領域に該当するかを判定してください。

    ## ユーザーの関心領域
    - 金融庁: 暗号資産、仮想通貨、暗号資産交換業、ブロックチェーン、Web3関連
    - 経済産業省: 補助金、助成金、支援金、給付金、事業支援制度
    - 厚生労働省: 社会保険、健康保険、厚生年金、雇用保険、労災保険、社会保障
    - デジタル庁: DX、デジタルトランスフォーメーション、マイナンバー、デジタル化推進
    - 総務省: 全般（フィルタなし、全件該当とする）
    - e-Gov: パブリックコメント（全件該当とする）

    ## 判定ルール
    - 該当する場合: relevant = true
    - 該当しない場合: relevant = false
    - 判断に迷う場合: relevant = true（見落とし防止を優先）
    - 総務省とe-Govは常にrelevant = true
    - categoryには該当する関心領域のキーワードを入れる

    ## 出力フォーマット
    JSONのみを出力してください。マークダウンのコードブロックや説明文は不要です。
  PROMPT

  def self.step1_user_prompt(articles)
    items = articles.map.with_index do |a, i|
      "#{i + 1}. [#{a[:source_name]}] #{a[:title]}"
    end.join("\n")

    <<~PROMPT
      以下の報道発表タイトルについて、関心領域に該当するか判定してください。

      #{items}

      以下のJSON配列形式で出力してください:
      [
        {"index": 1, "relevant": true, "category": "暗号資産"},
        {"index": 2, "relevant": false, "category": null},
        ...
      ]
    PROMPT
  end

  # ============================================================
  # Step 2: 要約・影響分析プロンプト
  # ============================================================
  # 入力: 記事の詳細ページ内容（HTML or テキスト）
  # 出力: 構造化された影響分析（4項目）
  #
  # ポイント:
  # - Step 1でrelevant=trueの記事のみに実行（コスト削減）
  # - 影響分析は4項目で構造化（何が変わる/誰に影響/いつから/必要な対応）
  # - LINEメッセージにそのまま使える形式で出力
  # ============================================================

  STEP2_SYSTEM = <<~PROMPT
    あなたは日本の規制・法改正の専門アナリストです。
    官公庁の報道発表の内容を分析し、構造化された影響分析を作成してください。

    ## 出力フォーマット
    以下の4項目で分析してください。各項目は1〜2文で簡潔に。
    情報が不明な項目は「情報なし」としてください。

    JSONのみを出力してください。マークダウンのコードブロックや説明文は不要です。

    {
      "what_changes": "何が変わるか（規制変更の概要）",
      "who_affected": "誰に影響があるか（影響を受ける主体）",
      "when": "いつから（施行日・適用開始日）",
      "action_required": "必要な対応（具体的に取るべきアクション）",
      "summary": "3行程度の要約"
    }
  PROMPT

  def self.step2_user_prompt(source_name, title, content)
    <<~PROMPT
      以下の報道発表について影響分析を行ってください。

      情報源: #{source_name}
      タイトル: #{title}

      --- 本文 ---
      #{content}
      --- 本文ここまで ---
    PROMPT
  end
end

# ============================================================
# Gemini API クライアント（プロトタイプ）
# ============================================================
module GeminiClient
  API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

  def self.generate(system_prompt, user_prompt, api_key:)
    require "net/http"
    require "json"
    require "uri"

    uri = URI.parse("#{API_URL}?key=#{api_key}")

    body = {
      system_instruction: {
        parts: [{ text: system_prompt }]
      },
      contents: [
        {
          role: "user",
          parts: [{ text: user_prompt }]
        }
      ],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 2048,
        responseMimeType: "application/json"
      }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Gemini API error: HTTP #{response.code} - #{response.body}"
    end

    result = JSON.parse(response.body)
    text = result.dig("candidates", 0, "content", "parts", 0, "text")

    JSON.parse(text)
  end
end

# ============================================================
# 使用例（サンプル実行イメージ）
# ============================================================
def demo
  puts "=" * 60
  puts "  AIプロンプト設計 - サンプル入出力"
  puts "=" * 60

  puts
  puts "Step 1: 関心領域判定"
  puts "-" * 60

  sample_articles = [
    { source_name: "金融庁", title: "暗号資産交換業者に対する新たなガイドラインの公表について" },
    { source_name: "金融庁", title: "令和7年3月期における金融再生法開示債権の状況等（ポイント）の公表" },
    { source_name: "経済産業省", title: "令和7年度補正予算「ものづくり補助金」の公募開始について" },
    { source_name: "経済産業省", title: "井野経済産業副大臣がオランダ王国を訪問しました" },
    { source_name: "厚生労働省", title: "健康保険法施行規則の一部を改正する省令案に関する意見募集" },
    { source_name: "厚生労働省", title: "歯科衛生士の業務に功績があった方を表彰" },
    { source_name: "デジタル庁", title: "マイナンバーカードを活用した行政手続のデジタル化推進について" },
    { source_name: "総務省", title: "令和7年度補正予算事業の交付決定" },
  ]

  puts
  puts "入力:"
  puts Prompts.step1_user_prompt(sample_articles)

  puts
  puts "期待される出力:"
  expected_step1 = [
    { index: 1, relevant: true, category: "暗号資産" },
    { index: 2, relevant: false, category: nil },
    { index: 3, relevant: true, category: "補助金" },
    { index: 4, relevant: false, category: nil },
    { index: 5, relevant: true, category: "社会保険" },
    { index: 6, relevant: false, category: nil },
    { index: 7, relevant: true, category: "DX・マイナンバー" },
    { index: 8, relevant: true, category: "全般" },
  ]
  puts JSON.pretty_generate(expected_step1)

  puts
  puts
  puts "Step 2: 要約・影響分析"
  puts "-" * 60

  sample_content = <<~CONTENT
    金融庁は、暗号資産交換業者に対する新たなガイドラインを公表しました。
    主な内容は以下の通りです。

    1. 顧客資産の分別管理要件の厳格化
       - コールドウォレットでの保管比率を95%以上に引き上げ
       - 第三者による定期監査の義務化

    2. AML/CFT対応の追加措置
       - トラベルルール対応の完全義務化
       - 高リスク取引の監視体制強化

    3. 利用者保護の強化
       - レバレッジ取引の上限引き下げ（現行4倍→2倍）
       - 広告・勧誘規制の強化

    本ガイドラインは2026年4月1日から適用されます。
    暗号資産交換業者は、施行日までに体制整備を完了する必要があります。
  CONTENT

  puts
  puts "入力:"
  puts Prompts.step2_user_prompt("金融庁", "暗号資産交換業者に対する新たなガイドラインの公表について", sample_content)

  puts
  puts "期待される出力:"
  expected_step2 = {
    what_changes: "暗号資産交換業者に対し、顧客資産の分別管理要件厳格化（コールドウォレット95%以上）、AML/CFT追加措置（トラベルルール完全義務化）、レバレッジ上限引き下げ（4倍→2倍）を求めるガイドラインが公表された。",
    who_affected: "暗号資産交換業者、関連サービス事業者",
    when: "2026年4月1日",
    action_required: "コールドウォレット保管比率の見直し、第三者監査体制の構築、トラベルルール対応、レバレッジ上限の変更対応、広告・勧誘体制の見直し",
    summary: "暗号資産交換業者への規制が大幅に強化される。顧客資産の分別管理要件厳格化、AML/CFT対応の追加措置、レバレッジ上限引き下げが主な変更点。2026年4月1日施行に向けた体制整備が必要。"
  }
  puts JSON.pretty_generate(expected_step2)

  puts
  puts
  puts "LINE通知メッセージ（上記から生成）"
  puts "-" * 60
  r = expected_step2
  msg = <<~MSG
    📋 【金融庁】暗号資産
    ━━━━━━━━━━━━━━━━━━━
    暗号資産交換業者に対する新たな
    ガイドラインの公表について

    ■ 何が変わる
    #{r[:what_changes]}

    ■ 誰に影響
    #{r[:who_affected]}

    ■ いつから
    #{r[:when]}

    ■ 必要な対応
    #{r[:action_required]}

    🔗 https://www.fsa.go.jp/news/...
    📅 2026-02-08
  MSG
  puts msg
end

demo if __FILE__ == $0
