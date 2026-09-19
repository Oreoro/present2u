module DeckTemplates
  class MlModel
    def self.title = "ML model card"

    def self.description = "Problem, data, architecture, training math, evaluation and deployment for a model."

    def self.manifest
      {
        deck: {
          title: "Model Card",
          subtitle: "Problem → data → training → evaluation",
          author: "Present2u",
          theme: "magenta",
          slides: [
            { type: "section", title: "Model Card", body: "A technical walkthrough", theme: "dark",
              notes: "A model card should let a reviewer reproduce and critique the system." },
            {
              type: "content", title: "Problem and data",
              body: <<~'MD',
                ## Framing

                - **Task**: inputs $x \in \mathcal{X}$, labels $y \in \mathcal{Y}$, loss $\mathcal{L}$.
                - **Data**: $N$ examples, label distribution, known leakage and imbalance.
                - **Splits**: train / validation / test by *time*, not random, when the deployment is temporal.

                ```latex
                \mathcal{L}(\theta) = -\frac{1}{N}\sum_{i=1}^{N} \log p_\theta(y_i \mid x_i)
                ```
              MD
              notes: "Leakage and split strategy explain most 'too good to be true' results." },
            {
              type: "content", title: "Architecture and training",
              body: <<~'MD',
                ## Objective and optimisation

                $$\theta^\star = \arg\min_\theta \; \mathcal{L}(\theta) + \lambda \lVert \theta \rVert_2^2$$

                - Optimiser, schedule, batch size, epochs, early stopping.
                - Regularisation: dropout, weight decay, augmentation.
                - Compute budget and wall-clock.

                ```python
                for x, y in loader:
                    loss = criterion(model(x), y)
                    loss.backward()
                    optimizer.step()
                    optimizer.zero_grad()
                ```
              MD
              notes: "Report the exact recipe; reproducibility is part of the result." },
            {
              type: "content", title: "Evaluation",
              body: <<~'MD',
                ## Metrics that match the decision

                | Metric | When it matters |
                | --- | --- |
                | Accuracy | balanced classes |
                | F1 / AUROC | imbalanced detection |
                | Calibration (ECE) | probabilities drive decisions |
                | Latency / cost | always |

                Always report **confidence intervals**, not just point estimates.
              MD
              notes: "A metric that doesn't match the downstream decision is decoration." },
            {
              type: "content", title: "Deployment and risks",
              body: <<~'MD',
                ## From notebook to service

                - **Serving**: batch vs real-time, quantisation, caching.
                - **Monitoring**: input drift, output drift, data quality, feedback loops.
                - **Failure modes**: distribution shift, spurious correlations, silent degradation.

                > Ship the evaluation harness before the model.
              MD
              notes: "Monitoring and rollback are part of the model, not an afterthought." }
          ]
        }
      }
    end
  end
end
