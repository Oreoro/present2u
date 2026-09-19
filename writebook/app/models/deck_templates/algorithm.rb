module DeckTemplates
  class Algorithm
    def self.title = "Algorithm deep dive"

    def self.description = "Problem statement, invariant, pseudocode, complexity and a proof sketch."

    def self.manifest
      {
        deck: {
          title: "Algorithm Deep Dive",
          subtitle: "Invariant → pseudocode → complexity → proof",
          author: "Present2u",
          theme: "orange",
          slides: [
            { type: "section", title: "Algorithm", body: "Correctness and cost", theme: "dark",
              notes: "For every algorithm: state the invariant, then derive correctness and complexity from it." },
            {
              type: "content", title: "Problem and invariant",
              body: <<~'MD',
                ## Define it precisely

                **Input / output.** State the exact contract, including edge cases ($n = 0$, ties, overflow).

                **Loop invariant.** A predicate $I$ that is true before and after each iteration:

                $$I \;\wedge\; \text{exit condition} \;\Rightarrow\; \text{postcondition}.$$
              MD
              notes: "An invariant is the single most useful tool for explaining why code is correct." },
            {
              type: "content", title: "Pseudocode",
              body: <<~'MD',
                ## Keep it executable-looking

                ```python
                def solve(items):
                    # invariant: best is optimal for items[:i]
                    best = None
                    for i, item in enumerate(items):
                        best = combine(best, item)
                    return best
                ```

                Then map each line to the invariant: initialisation, maintenance, termination.
              MD
              notes: "Pseudocode should expose the invariant, not the language." },
            {
              type: "content", title: "Complexity",
              body: <<~'MD',
                ## Time and space

                $$T(n) = T(n/2) + O(n) \;\Rightarrow\; T(n) = O(n \log n).$$

                | Case | Time | Space |
                | --- | --- | --- |
                | Best | $O(n \log n)$ | $O(\log n)$ |
                | Average | $O(n \log n)$ | $O(\log n)$ |
                | Worst | $O(n^2)$ | $O(n)$ |

                State the model of computation and what $n$ counts.
              MD
              notes: "Recurrences and the Master theorem turn complexity into a one-liner." },
            {
              type: "content", title: "Proof sketch",
              body: <<~'MD',
                ## Correctness in three lines

                1. **Initialisation** — $I$ holds before the first iteration.
                2. **Maintenance** — if $I$ holds and the guard is true, $I$ holds after the body.
                3. **Termination** — the loop ends and $I$ plus the exit condition gives the postcondition.

                Combine with a cost argument for the bound.
              MD
              notes: "The proof is short when the invariant is right; if it's long, the invariant is wrong." }
          ]
        }
      }
    end
  end
end
