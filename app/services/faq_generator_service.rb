require "net/http"
require "json"
require "securerandom"

class FaqGeneratorService
  DEFAULT_MODEL = ENV.fetch("HF_MODEL", "google/flan-t5-large")
  HF_ENDPOINT = ->(model) { "https://api-inference.huggingface.co/models/#{model}" }

  def initialize(content_body, model: DEFAULT_MODEL)
    @body = content_body.to_s
    @model = model
  end


  def call
    prompt = build_prompt(@body)
    payload = { inputs: prompt, parameters: { max_new_tokens: 512, temperature: 0.2 } }.to_json

    uri = URI(HF_ENDPOINT.call(@model))
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
      Convert the following content into a JSON array of FAQs for customers.
      Output must be valid JSON (an array of objects). Each object must have keys: "question" and "answer".
      Rules:
      - Use plain, non-technical language.
      - Produce at most 8 FAQs.
      - Keep answers short (1-3 sentences).
      - Do not output any text outside the JSON array.

      Content:
      """#{' '}
      #{text}
      """
    PROMPT
  end


  def parse_response(body)
    begin
      parsed = JSON.parse(body)

      if parsed.is_a?(Array) && parsed.first.is_a?(Hash) && parsed.first.key?("generated_text")
        text = parsed.map { |e| e["generated_text"] }.join("\n")
      elsif parsed.is_a?(Hash) && parsed["generated_text"]
        text = parsed["generated_text"]
      else

        if parsed.is_a?(Array) && parsed.all? { |o| o.is_a?(Hash) && o["question"] && o["answer"] }
          return parsed
        end
        text = body.to_s
      end
    rescue JSON::ParserError
      text = body.to_s
    end


    if (match = text.match(/(\[.*\])/m))
      json_text = match[1]
      begin
        json = JSON.parse(json_text)
        return json if json.is_a?(Array) && json.all? { |o| o["question"] && o["answer"] }
      rescue JSON::ParserError
      end
    end

    nil
  end


  def fallback_from_text(text)
    paras = text.split(/\n{2,}/).map(&:strip).reject(&:empty?).first(6)
    paras.map.with_index do |p, i|
      {
        "question" => "About: #{p.truncate(60)}?",
        "answer" => p.split("\n").first.truncate(280)
      }
    end
  end
end
