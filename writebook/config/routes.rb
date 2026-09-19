Rails.application.routes.draw do
  root "books#index"

  resource :first_run, only: %i[ show create ]

  resource :session, only: %i[ new create destroy ] do
    scope module: "sessions" do
      resources :transfers, only: %i[ show update ]
    end
  end

  get "join/:join_code", to: "users#new", as: :join
  post "join/:join_code", to: "users#create"

  resource :account do
    scope module: "accounts" do
      resource :join_code, only: :create
      resource :custom_styles, only: %i[ edit update ]
    end
  end

  # Customer-facing URLs say decks and slides; models stay Book/Leaf internally.
  resources :books, path: "decks", except: %i[ index show ] do
    resource :publication, path: "share", controller: "books/publications", only: %i[ show edit update ]
    resource :bookmark, path: "resume", controller: "books/bookmarks", only: :show

    scope module: "books" do
      namespace :leaves, path: "slides" do
        resources :moves, only: :create
      end

      resource :search
    end

    resources :sections, path: "section_slides"
    resources :pictures, path: "image_slides"
    resources :pages, path: "content_slides"
    resources :typsts, path: "typst_slides" do
      post :preview, on: :collection
    end
  end

  get "/decks/:id/:slug", to: "books#show", constraints: { id: /\d+/ }, as: :slugged_book
  get "/decks/:book_id/:book_slug/:id/:slug", to: "leafables#show", constraints: { book_id: /\d+/, id: /\d+/ }, as: :slugged_leafable

  direct :book_slug do |book, options|
    route_for :slugged_book, book, book.slug, options
  end

  direct :leafable_slug do |leaf, options|
    route_for :slugged_leafable, leaf.book, leaf.book.slug, leaf, leaf.slug, options
  end

  resources :pages, only: [], path: "slides" do
    scope module: "pages" do
      resources :edits, only: :show
    end
  end

  resources :qr_code, only: :show
  resources :users do
    scope module: "users" do
      resource :profile
      resource :api_token, only: :create
    end
  end

  get  "templates", to: "deck_templates#index", as: :deck_templates
  post "templates/:key", to: "deck_templates#create", as: :deck_template

  get "api", to: "api/docs#show", as: :api_docs

  namespace :api do
    post "compile", to: "compiles#create", as: :compile
    post "compose", to: "composes#create", as: :compose
    post "export", to: "exports#create", as: :export
    get  "schema", to: "schema#show", as: :schema
    get  "toolchain", to: "toolchain#show", as: :toolchain

    resources :decks, only: %i[ index show create update destroy ] do
      post :import, on: :collection
      post :plan, on: :member
      post :apply, on: :member
      resources :slides, only: %i[ create update destroy ]
    end

    get  "templates", to: "templates#index", as: :templates
    post "templates/:key", to: "templates#create", as: :template
  end

  direct :leafable do |leaf, options|
    route_for "book_#{leaf.leafable_name}", leaf.book, leaf, options
  end

  direct :edit_leafable do |leaf, options|
    route_for "edit_book_#{leaf.leafable_name}", leaf.book, leaf, options
  end

  get "context_dev/search", to: "context_dev#search", as: :context_dev_search
  get "rendered/:filename", to: "rendered_assets#show", as: :rendered_asset,
    constraints: { filename: /[a-f0-9]{64}\.svg/ }

  namespace :action_text, path: nil do
    get "/u/*slug" => "markdown/uploads#show", as: :markdown_upload
    post "/uploads" => "markdown/uploads#create", as: :markdown_uploads
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
