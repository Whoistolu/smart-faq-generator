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
    Generate 5–8 FAQ questions and answers based on the text below. 
    Return ONLY valid JSON in the format:
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
    parsed = JSON.parse(body)

    if parsed.is_a?(Hash) && parsed["choices"]
      content = parsed["choices"].first.dig("message", "content")
      if content
        if (match = content.match(/(\[.*\])/m))
          json_text = match[1]
          begin
            json = JSON.parse(json_text)
            return json if json.is_a?(Array) && json.all? { |o| o["question"] && o["answer"] }
          rescue JSON::ParserError
          end
        end
      end
    end

    nil
  rescue JSON::ParserError
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
