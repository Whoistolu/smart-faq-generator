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
    Return **only** valid JSON. Do not add explanations or extra text. If you cannot, return an empty JSON array.
    You are an FAQ generator for businesses.
    Given the following product or service description, extract 5-10 clear and concise FAQs with helpful answers.
    Return the result strictly in JSON format with keys "question" and "answer".
      Rules:
      - Use plain, non-technical language.
      - Produce at most 8 FAQs.
      - Keep answers short (1-3 sentences).
      - Do not output any text outside the JSON array.

      Description:
      """#{' '}
      #{text}
      """
    PROMPT
  end


  def parse_response(body)
    Rails.logger.debug("[FaqGeneratorService] Raw API response: #{body.inspect}")
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
    sentences = text.split(/\. |\n/).map(&:strip).reject(&:empty?).first(6)
    sentences.map.with_index do |s, i|
      {
        "question" => "What should I know about: #{s.truncate(60)}?",
        "answer" => s.truncate(280)
      }
    end
  end
end
