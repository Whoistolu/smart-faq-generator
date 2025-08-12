class Content < ApplicationRecord
  has_many :faqs, dependent: :destroy

  validates :body, :slug, presence: true
  validates :slug, uniqueness: true

  before_validation :set_slug, on: :create

  private

  def set_slug
    self.slug ||= SecureRandom.alphanumeric(8).downcase
  end
end
