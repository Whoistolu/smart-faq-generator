class Faq < ApplicationRecord
  belongs_to :content
  validates :question, :answer, presence: true
end
