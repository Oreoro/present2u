class FirstRun
  ACCOUNT_NAME = "Present2u"

  def self.create!(user_params)
    account = Account.create!(name: ACCOUNT_NAME, embed_providers: EmbedProvider::DEFAULTS)

    User.create!(user_params.merge(role: :administrator)).tap do |user|
      DeckBuilder.create!(user: user, manifest: DeckTemplates::Einstein.manifest)
    end
  end
end
