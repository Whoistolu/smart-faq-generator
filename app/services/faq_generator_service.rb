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
      max_tokens: 1024,
      response_format: { type: "json_object" }
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
    fallback_from_text(@body)
  end

  private

  def build_prompt(text)
    <<~PROMPT
    You are an FAQ generator.
    Generate 5–8 FAQ questions and answers based on the text below.#{' '}
    Respond with ONLY valid JSON in this exact format, with no extra commentary:
    Given this text:

    "#{@body}"

    Return only valid JSON in this format:
    [
      {"question": "string", "answer": "string"},
      ...
    ]

    Text:
    #{text}
    PROMPT
  end

  
def parse_response(body)
  return nil if body.blank?

  begin
    parsed = JSON.parse(body)

    if parsed.is_a?(Hash) && parsed["choices"]
      content = parsed.dig("choices", 0, "message", "content")

      begin
        inner = JSON.parse(content)

        if inner.is_a?(Hash) && inner["response"]
          response = inner["response"]

          response = JSON.parse(response) if response.is_a?(String)
          if response.is_a?(Array) && response.all? { |o| o["question"] && o["answer"] }
            return response
          end
        end

        if inner.is_a?(Array) && inner.all? { |o| o["question"] && o["answer"] }
          return inner
        elsif inner.is_a?(Hash) && inner["question"] && inner["answer"]
          return [inner]
        end
      rescue JSON::ParserError
      end
    end

    if parsed.is_a?(Array) && parsed.all? { |o| o["question"] && o["answer"] }
      return parsed
    end

    if parsed.is_a?(Hash) && parsed["faqs"].is_a?(Array)
      return parsed["faqs"].select { |o| o["question"] && o["answer"] }
    end
  rescue JSON::ParserError
  end

  if (match = body.match(/\[.*\]/m))
    json_str = match[0]
    begin
      faqs = JSON.parse(json_str)
      if faqs.is_a?(Array) && faqs.all? { |o| o["question"] && o["answer"] }
        return faqs
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[FaqGeneratorService] Regex JSON recovery failed: #{e.message}")
    end
  end

  nil
end




  def fallback_from_text(text)
    sentences = text.split(/\. |\n/).map(&:strip).reject(&:empty?).first(6)
    sentences.map do |s|
      {
        "question" => "What is important about '#{s.truncate(50)}'?",
        "answer"   => s.truncate(200)
      }
    end
  end
end
