require "net/http"
require "json"
require "securerandom"

class FaqGeneratorService
  HF_ENDPOINT = "https://router.huggingface.co/v1/chat/completions"
  DEFAULT_MODEL = ENV.fetch("HF_MODEL", "zai-org/GLM-4.5:fireworks-ai")

  def initialize(content_body, model: DEFAULT_MODEL)
    @body = content_body.to_s
    @model = model
  end

  def call
    prompt = build_prompt(@body)

    payload = {
      model: @model,
      messages: [
        { role: "user", content: prompt }
      ],
      stream: false,
      temperature: 0.2,
      max_tokens: 512
    }.to_json

    uri = URI(HF_ENDPOINT)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{ENV['HF_API_KEY']}"
    req["Content-Type"] = "application/json"
    req.body = payload

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 60) do |http|
      http.request(req)
    end

    parse_response(res.body) || fallback_from_text(@body)
  rescue => e
    Rails.logger.error("[FaqGeneratorService] #{e.class}: #{e.message}")
    fallback_from_text(@body)
  end

  private

  def build_prompt(text)
    <<~PROMPT
    Generate 5–8 FAQ questions and answers based on the text below.#{' '}
    Respond with ONLY valid JSON in this exact format, with no extra commentary:

    [
      {"question": "string", "answer": "string"},
      ...
    ]

    Text:
    #{text}
    PROMPT
  end

  
def parse_response(body)
    Rails.logger.debug("[FaqGeneratorService] Raw API response: #{body.inspect}")

    begin
      parsed = JSON.parse(body)

      if parsed.is_a?(Array) && parsed.first.is_a?(Hash) && parsed.first.key?("generated_text")
        text = parsed.map { |e| e["generated_text"] }.join("\n")

      elsif parsed.is_a?(Hash) && parsed.dig("choices", 0, "message", "content")
        text = parsed.dig("choices", 0, "message", "content")

        begin
          inner_json = JSON.parse(text)
          return inner_json if inner_json.is_a?(Array) &&
                              inner_json.all? { |o| o["question"] && o["answer"] }
        rescue JSON::ParserError
          # not valid JSON, continue fallback
        end

      elsif parsed.is_a?(Array) && parsed.all? { |o| o.is_a?(Hash) && o["question"] && o["answer"] }
        return parsed

      elsif parsed.is_a?(Hash) && parsed["faqs"].is_a?(Array)
        return parsed["faqs"].select { |o| o["question"] && o["answer"] }
      else
        text = body.to_s
      end
    rescue JSON::ParserError
      text = body.to_s
    end

    if (match = text.match(/\[.*\]/m))
      json_text = match[0]
      begin
        json = JSON.parse(json_text)
        return json if json.is_a?(Array) && json.all? { |o| o["question"] && o["answer"] }
      rescue JSON::ParserError => e
        Rails.logger.error("[FaqGeneratorService] JSON parse failed: #{e.message}")
      end
    end

    nil
  end


  def fallback_from_text(text)
    sentences = text.split(/\. |\n/).map(&:strip).reject(&:empty?).first(6)
    sentences.map do |s|
      {
        "question" => "What is important about '#{s.truncate(50)}'?",
        "answer" => s.truncate(200)
      }
    end
  end
end
