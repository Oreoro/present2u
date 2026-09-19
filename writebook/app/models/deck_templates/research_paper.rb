module DeckTemplates
  class ResearchPaper
    def self.title = "Research paper walkthrough"

    def self.description = "Abstract, motivation, method, results and related work for a paper reading group."

    def self.manifest
      {
        deck: {
          title: "Paper Walkthrough",
          subtitle: "Reading group",
          author: "Present2u",
          theme: "white",
          slides: [
            { type: "section", title: "Paper Walkthrough", body: "Claim → method → evidence", theme: "dark",
              notes: "Lead with the claim and the evidence; save the details for questions." },
            {
              type: "content", title: "Claim and motivation",
              body: <<~'MD',
                ## What the paper claims

                - **One-sentence claim.**
                - **Why now?** What was blocking progress before.
                - **Contribution list** — what is genuinely new.

                > If you can't state the claim in one sentence, you haven't understood the paper yet.
              MD
              notes: "Separate the claim from the method; reviewers attack the claim, not the method." },
            {
              type: "content", title: "Method",
              body: <<~'MD',
                ## The core idea

                State the objective and the key equation:

                $$\hat{\theta} = \arg\min_\theta \; \mathbb{E}_{(x,y)\sim\mathcal{D}}\left[\mathcal{L}(f_\theta(x), y)\right].$$

                Then the two or three implementation details that actually matter.
              MD
              notes: "Most papers have one load-bearing idea; find it and explain only that." },
            {
              type: "content", title: "Evidence",
              body: <<~'MD',
                ## Results and ablations

                | Experiment | Metric | Baseline | This work |
                | --- | --- | --- | --- |
                | Main | — | — | — |
                | Ablation | — | — | — |

                Ask: is the comparison **controlled**? Are error bars reported? Is the gain inside noise?
              MD
              notes: "Ablations are where you learn what the method actually depends on." },
            {
              type: "content", title: "Limitations and related work",
              body: <<~'MD',
                ## Where it breaks

                - Assumptions the method relies on.
                - Settings where the baseline is still better.
                - The two papers that most threaten the claim.

                > The limitations section is usually the most honest part of a paper.
              MD
              notes: "Related work is a map of the field; place the paper on it." }
          ]
        }
      }
    end
  end
end
