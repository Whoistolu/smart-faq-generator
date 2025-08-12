Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :contents, only: [:create, :show] do
        get :faqs, on: :member
      end

      get '/faqs/public/:slug', to: 'public_faqs#show'
    end
  end
end
