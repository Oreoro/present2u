# Registry of ready-made technical deck manifests. Agents and people can list
# these over the API and instantiate one as a starting point.
module DeckTemplate
  REGISTRY = {
    "einstein" => "DeckTemplates::Einstein",
    "transformer" => "DeckTemplates::Transformer",
    "raft" => "DeckTemplates::Raft",
    "system-design" => "DeckTemplates::SystemDesign",
    "ml-model" => "DeckTemplates::MlModel",
    "algorithm" => "DeckTemplates::Algorithm",
    "research-paper" => "DeckTemplates::ResearchPaper",
    "incident-review" => "DeckTemplates::IncidentReview"
  }.freeze

  class << self
    def all
      REGISTRY.keys.filter_map { |key| find(key) }
    end

    def find(key)
      klass = REGISTRY[key.to_s]&.constantize
      return unless klass

      {
        key: key.to_s,
        title: klass.title,
        description: klass.description,
        slides: klass.manifest.dig(:deck, :slides)&.size.to_i,
        manifest: klass.manifest
      }
    end
  end
end
