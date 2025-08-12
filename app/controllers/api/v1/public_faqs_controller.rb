class Api::V1::PublicFaqsController < ApplicationController
      def show
        content = Content.find_by!(slug: params[:slug])
        render json: {
          slug: content.slug,
          faqs: content.faqs.select(:question, :answer)
        }
      end
end
