class Api::V1::ContentsController < ApplicationController
  def create
    Rails.logger.info("[ContentsController#create] Starting content creation")

    content = Content.new(content_params)
    if content.save
      Rails.logger.info("[ContentsController#create] Saved content ID=#{content.id}, Slug=#{content.slug}")

      faqs = FaqGeneratorService.new(content.body).call
      Rails.logger.info("[ContentsController#create] Generated #{faqs.size} raw FAQs")

      faqs.each_with_index do |f, i|
        if f["question"].present? && f["answer"].present?
          content.faqs.create!(question: f["question"].strip, answer: f["answer"].strip)
          Rails.logger.debug("[ContentsController#create] Saved FAQ ##{i+1} for content #{content.id}")
        else
          Rails.logger.warn("[ContentsController#create] Skipped FAQ ##{i+1} due to missing data: #{f.inspect}")
        end
      end

      render json: content_response(content), status: :created
    else
      Rails.logger.error("[ContentsController#create] Failed to save content: #{content.errors.full_messages}")
      render json: { errors: content.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    content = Content.find(params[:id])
    render json: content_response(content)
  end

  def faqs
    content = Content.find(params[:id])
    render json: { faqs: content.faqs.select(:id, :question, :answer) }
  end

  private

  def content_params
    params.require(:content).permit(:body)
  end

  def content_response(content)
    {
      id: content.id,
      slug: content.slug,
      faqs: content.faqs.select(:id, :question, :answer)
    }
  end
end
