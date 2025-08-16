class Api::V1::ContentsController < ApplicationController
  def create
    content = Content.new(content_params)

    if content.save
      begin
        faqs = FaqGeneratorService.new(content.body).call
        faqs.each do |f|
          next unless f["question"].present? && f["answer"].present?
          content.faqs.create!(question: f["question"].strip, answer: f["answer"].strip)
        end
      rescue => e
        Rails.logger.error("FAQ generation failed: #{e.message}")
      end

      render json: content_response(content), status: :created
    else
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
