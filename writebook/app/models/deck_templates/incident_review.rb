module DeckTemplates
  class IncidentReview
    def self.title = "Incident review"

    def self.description = "Blameless timeline, root cause, impact and action items for a postmortem."

    def self.manifest
      {
        deck: {
          title: "Incident Review",
          subtitle: "Blameless postmortem",
          author: "Present2u",
          theme: "black",
          slides: [
            { type: "section", title: "Incident Review", body: "Timeline · cause · impact · actions", theme: "dark",
              notes: "Blameless: we are reviewing systems and decisions, never people." },
            {
              type: "content", title: "Summary and impact",
              body: <<~'MD',
                ## At a glance

                | Field | Value |
                | --- | --- |
                | Severity | SEV-? |
                | Duration | start → end |
                | User impact | requests failed, data affected |
                | Detection | alert / customer report |

                **Error budget:** $1 - \dfrac{\text{successful requests}}{\text{total requests}}$.
              MD
              notes: "Quantify impact with the same metrics the service is measured by." },
            {
              type: "content", title: "Timeline",
              body: <<~'MD',
                ## What happened, in order

                - **T+0** — change deployed.
                - **T+4m** — alert fires.
                - **T+11m** — mitigation attempted.
                - **T+26m** — rollback, recovery begins.
                - **T+41m** — fully recovered.

                Times are from the monitoring system, not memory.
              MD
              notes: "A precise timeline separates detection latency from mitigation latency." },
            {
              type: "content", title: "Root cause",
              body: <<~'MD',
                ## Causal chain

                ```d2
                direction: down
                change: "Config change"
                cache: "Cache key mismatch"
                load: "Cache miss storm"
                db: "Database overload"
                out: "Timeouts + errors"

                change -> cache -> load -> db -> out
                ```
              MD
              notes: "Keep asking 'why' until the answer is a control that failed, not a person." },
            {
              type: "content", title: "Action items",
              body: <<~'MD',
                ## Prevent, detect, mitigate

                | Action | Type | Owner | Due |
                | --- | --- | --- | --- |
                | Add config validation | Prevent | — | — |
                | Alert on cache hit-rate | Detect | — | — |
                | One-command rollback | Mitigate | — | — |

                Every action has an owner and a date, or it is not an action.
              MD
              notes: "Prevent, detect, mitigate: a balanced set of actions, each with an owner." }
          ]
        }
      }
    end
  end
end
