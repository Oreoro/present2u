module DeckTemplates
  class Raft
    def self.title = "Raft — understandable consensus"

    def self.description = "Leader election, log replication and safety in a distributed consensus protocol."

    def self.manifest
      {
        deck: {
          title: "Raft",
          subtitle: "Consensus you can reason about",
          author: "Present2u",
          theme: "green",
          slides: [
            { type: "section", title: "Raft", body: "Leader election · log replication · safety", theme: "dark",
              notes: "Raft is designed for understandability: decompose consensus into independent pieces." },
            {
              type: "content", title: "The problem",
              body: <<~'MD',
                ## Consensus in an unreliable world

                A cluster of $N$ servers must agree on a single ordered log despite crashes and partitions.

                - Tolerates $f$ failures with $N = 2f + 1$ servers.
                - Safety is never violated; liveness requires a majority to be reachable.
                - A **term** is a logical clock: monotonically increasing, one leader per term.
              MD
              notes: "Majority quorums are what make agreement possible: any two majorities intersect." },
            {
              type: "content", title: "States and transitions",
              body: <<~'MD',
                ## Three states

                ```d2
                direction: right
                follower: Follower { shape: oval }
                candidate: Candidate { shape: hexagon }
                leader: Leader { shape: double_circle }

                follower -> candidate: "election timeout"
                candidate -> candidate: "split vote, new term"
                candidate -> leader: "majority of votes"
                candidate -> follower: "higher term"
                leader -> follower: "higher term"
                ```
              MD
              notes: "Randomised election timeouts are the trick that avoids persistent split votes." },
            {
              type: "content", title: "Log replication",
              body: <<~'MD',
                ## AppendEntries

                The leader sends `AppendEntries(term, prevLogIndex, prevLogTerm, entries, commitIndex)`.

                A follower accepts only if its log matches at `prevLogIndex/prevLogTerm`. On conflict it rejects and the leader backs up, overwriting divergent suffixes.

                > **Log Matching Property** — if two logs contain an entry with the same index and term, the logs are identical through that index.
              MD
              notes: "The prevLogIndex/prevLogTerm check is the induction step of the Log Matching Property." },
            {
              type: "content", title: "Election safety",
              body: <<~'MD',
                ## Why one leader per term

                A candidate increments its term, votes for itself, and requests votes. Each server votes **once per term**, first-come-first-served.

                A leader needs a majority of votes, so two leaders in the same term would require two majorities — impossible, because any two majorities intersect.

                $$|Q_1 \cap Q_2| \ge 1 \quad \text{for quorums } Q_1, Q_2.$$
              MD
              notes: "This is the same quorum-intersection argument behind Paxos and quorum replication." },
            {
              type: "content", title: "References",
              body: <<~'MD',
                - Ongaro, D., Ousterhout, J. (2014). *In Search of an Understandable Consensus Algorithm.* USENIX ATC.
                - Ongaro, D. (2014). *Consensus: Bridging Theory and Practice.* PhD thesis.
                - The Raft website: [raft.github.io](https://raft.github.io)
              MD
              notes: "The thesis has the full proof of the Log Matching and Leader Completeness properties." }
          ]
        }
      }
    end
  end
end
