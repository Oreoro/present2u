module DeckTemplates
  class SystemDesign
    def self.title = "System design review"

    def self.description = "Context, requirements, architecture diagram, data flow, capacity math and tradeoffs."

    def self.manifest
      {
        deck: {
          title: "System Design Review",
          subtitle: "From requirements to tradeoffs",
          author: "Present2u",
          theme: "blue",
          slides: [
            { type: "section", title: "System Design", body: "Requirements → architecture → tradeoffs", theme: "dark",
              notes: "Start with constraints, not boxes. Every diagram decision should trace to a requirement." },
            {
              type: "content", title: "Requirements",
              body: <<~'MD',
                ## Functional and non-functional

                **Functional**
                - Reads and writes, core entities, consistency expectations.

                **Non-functional**
                - Peak QPS: $Q$, p99 latency budget $L$, availability target $A$.
                - Data size and growth: $D$ bytes/day, retention $R$ days.

                ```latex
                \text{Capacity} = Q \times \text{payload} \times 86400
                ```
              MD
              notes: "Make the numbers explicit; back-of-envelope math exposes infeasible designs early." },
            {
              type: "content", title: "Architecture",
              body: <<~'MD',
                ## High-level topology

                ```d2
                direction: right
                client: Client { shape: person }
                lb: "Load balancer" { shape: hexagon }
                api: "API service"
                cache: "Cache" { shape: cylinder }
                db: "Primary DB" { shape: cylinder }
                replica: "Read replica" { shape: cylinder }
                queue: "Queue"
                worker: Worker

                client -> lb -> api
                api -> cache
                api -> db
                api -> queue -> worker
                db -> replica
                worker -> db
                ```
              MD
              notes: "Keep the first diagram coarse; drill into the hot path only." },
            {
              type: "content", title: "Capacity math",
              body: <<~'MD',
                ## Back-of-the-envelope

                | Quantity | Formula | Example |
                | --- | --- | --- |
                | Write throughput | $Q_w$ | $5{,}000\ \text{rps}$ |
                | Storage/day | $Q_w \times \text{size} \times 86400$ | $43\ \text{GB}$ |
                | Cache working set | $Q_r \times 0.2 \times \text{size}$ | $8\ \text{GB}$ |
                | Replicas | $\lceil Q_r / q_{\text{node}} \rceil$ | $12$ |
              MD
              notes: "Numbers turn architecture debates into arithmetic." },
            {
              type: "content", title: "Tradeoffs",
              body: <<~'MD',
                ## Every choice costs something

                - **Consistency vs availability** — quorum reads/writes, or eventual convergence.
                - **Latency vs durability** — synchronous replication vs async with a bounded window.
                - **Cost vs headroom** — over-provision for peaks, or autoscale with cold-start risk.

                > State the tradeoff, the assumption behind it, and the signal that would make you revisit it.
              MD
              notes: "A design review is really a review of tradeoffs and their assumptions." }
          ]
        }
      }
    end
  end
end
