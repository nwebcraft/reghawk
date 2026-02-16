# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module RegHawk
  module AiAnalyzer
    GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

    # ============================================================
    # Step 1: 関心領域判定（バッチ）
    # ============================================================
    def self.judge_relevance(articles, sources)
      # ソースごとの関心領域マップを構築
      interest_map = sources.each_with_object({}) do |s, h|
        h[s["key"]] = s["interest"]
      end

      # 総務省・e-Govは常にrelevant（API呼び出し不要）
      results = articles.map do |a|
        if interest_map[a["source"]].nil?
          { "relevant" => true, "category" => "全般" }
        else
          nil # 後でAPIで判定
        end
      end

      # API判定が必要な記事だけ抽出
      to_judge = articles.each_with_index.select { |_, i| results[i].nil? }

      if to_judge.any?
        items = to_judge.map.with_index do |(a, _), idx|
          "#{idx + 1}. [#{a["source_name"]}] #{a["title"]}"
        end.join("\n")

        system_prompt = build_step1_system_prompt(interest_map)
        user_prompt = <<~PROMPT
          以下の報道発表タイトルについて、関心領域に該当するか判定してください。

          #{items}

          以下のJSON配列形式で出力してください:
          [{"index": 1, "relevant": true, "category": "暗号資産"}, ...]
        PROMPT

        response = call_gemini(system_prompt, user_prompt)
        judgments = JSON.parse(response) rescue []

        to_judge.each_with_index do |(_, original_idx), judge_idx|
          j = judgments.find { |x| x["index"] == judge_idx + 1 }
          results[original_idx] = if j
            { "relevant" => j["relevant"], "category" => j["category"] }
          else
            { "relevant" => false, "category" => nil }
          end
        end
      end

      results
    end

    # ============================================================
    # Step 2: 要約・影響分析
    # ============================================================
    def self.analyze_impact(source_name, title, content)
      system_prompt = <<~PROMPT
        あなたは日本の規制・法改正の専門アナリストです。
        官公庁の報道発表の内容を分析し、構造化された影響分析を作成してください。

        以下の5項目をJSON形式で出力してください。各項目は1〜2文で簡潔に。
        情報が不明な項目は「情報なし」としてください。
        JSONのみを出力してください。

        {
          "what_changes": "何が変わるか",
          "who_affected": "誰に影響があるか",
          "when": "いつから",
          "action_required": "必要な対応",
          "summary": "3行程度の要約"
        }
      PROMPT

      user_prompt = <<~PROMPT
        情報源: #{source_name}
        タイトル: #{title}

        --- 本文 ---
        #{content}
      PROMPT

      response = call_gemini(system_prompt, user_prompt)
      JSON.parse(response)
    end

    private

    def self.build_step1_system_prompt(interest_map)
      interests = interest_map.map do |key, value|
        next if value.nil?
        "- #{key}: #{value}"
      end.compact.join("\n")

      <<~PROMPT
        あなたは日本の規制・法改正動向の分析アシスタントです。
        官公庁の報道発表タイトルを見て、ユーザーの関心領域に該当するかを判定してください。

        ## ユーザーの関心領域
        #{interests}

        ## 判定ルール
        - 該当する場合: relevant = true
        - 該当しない場合: relevant = false
        - 判断に迷う場合: relevant = true（見落とし防止を優先）

        ## 出力フォーマット
        JSONのみを出力してください。
      PROMPT
    end

    def self.call_gemini(system_prompt, user_prompt)
      api_key = ENV.fetch("REGHAWK_GEMINI_API_KEY")
      uri = URI.parse("#{GEMINI_URL}?key=#{api_key}")

      body = {
        system_instruction: { parts: [{ text: system_prompt }] },
        contents: [{ role: "user", parts: [{ text: user_prompt }] }],
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
        raise "Gemini API error: #{response.code} - #{response.body}"
      end

      result = JSON.parse(response.body)
      result.dig("candidates", 0, "content", "parts", 0, "text")
    end
  end
end
