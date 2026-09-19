# Seeds a ready-to-use Present2u install: one account, one administrator and a
# couple of technical demo decks. Idempotent — safe to run repeatedly.
#
#   bin/rails db:seed
#
# Sign in with presenter@example.com / password123 (change it in Settings).
if User.none?
  Account.create!(name: "Present2u", embed_providers: EmbedProvider::DEFAULTS)

  user = User.create!(
    name: "Presenter",
    email_address: "presenter@example.com",
    password: "password123",
    role: :administrator
  )

  DeckBuilder.create!(user: user, manifest: DeckTemplates::Einstein.manifest)
  DeckBuilder.create!(user: user, manifest: DeckTemplates::Transformer.manifest)

  puts "Seeded presenter@example.com / password123 with 2 demo decks."
else
  puts "Users already exist; skipping seed."
end