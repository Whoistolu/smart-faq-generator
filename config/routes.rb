Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :contents, only: [:create, :show] do
        member do
          get :faqs
        end
      end

      get "faqs/public/:slug", to: "public_faqs#show"
    end
  end
end
