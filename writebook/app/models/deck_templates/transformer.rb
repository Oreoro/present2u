module DeckTemplates
  # A deep technical walkthrough of the Transformer: equations, architecture
  # diagrams, tensor shapes, reference code, inference engineering and scaling.
  class Transformer
    def self.title = "Attention Is All You Need — the Transformer"

    def self.description = "Architecture, equations, tensor shapes, PyTorch code, inference and scaling."

    def self.manifest
      {
        deck: {
          title: "Attention Is All You Need",
          subtitle: "The Transformer, from equations to engineering",
          author: "Present2u",
          theme: "violet",
          slides: slides
        }
      }
    end

    def self.slides
      [
        {
          type: "section", title: "Attention Is All You Need", body: "The Transformer, end to end", theme: "dark",
          notes: "Vaswani et al., 2017. A sequence model with no recurrence — only attention. Three parts: why attention, the architecture, engineering at scale."
        },
        {
          type: "section", title: "Part I — Why attention", body: "Sequential models hit a wall", theme: "dark",
          notes: "Start from the limitation that motivated the architecture."
        },
        {
          type: "content", title: "The problem with recurrence",
          body: <<~'MD',
            ## Recurrent models are sequential by construction

            An RNN compresses the past into a hidden state and advances one step at a time:

            $$h_t = f(h_{t-1}, x_t), \qquad y_t = g(h_t).$$

            Two consequences:

            - **No parallelism over time** — step $t$ needs step $t-1$. Training on a length-$n$ sequence costs $O(n)$ sequential operations.
            - **Long-range paths** — information from token $1$ to token $n$ travels through $O(n)$ steps, and gradients vanish.

            Attention removes the bottleneck: every position can look at every other position **in one step**.
          MD
          notes: "The key claim of the paper: replace recurrence with attention to get O(1) sequential ops and O(1) path length."
        },
        {
          type: "content", title: "Attention as a soft lookup (sketch)", sketch: true,
          body: <<~'MD',
            ## Query, key, value

            ```d2-sketch
            direction: right
            query: "Query: what am I looking for?"
            keys: "Keys: what do I contain?" { shape: cylinder }
            values: "Values: what do I offer?" { shape: cylinder }
            attn: "match + softmax" { shape: cloud }
            out: "weighted sum"

            query -> attn
            keys -> attn
            values -> attn
            attn -> out
            ```

            Every token asks a question ($Q$), every other token advertises a key ($K$), and the answer is a weighted average of their values ($V$). Training shapes $W^Q, W^K, W^V$ so the questions and answers line up.
          MD
          notes: "The dictionary analogy is the cleanest intuition for attention; sketch mode makes it feel like a whiteboard."
        },
        {
          type: "content", title: "Scaled dot-product attention",
          body: <<~'MD',
            ## The core operation

            Given queries $Q$, keys $K$ and values $V$,

            $$\mathrm{Attention}(Q, K, V) = \mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}}\right) V.$$

            ```latex
            \begin{align}
              \mathrm{Attention}(Q,K,V)
                &= \mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}}\right) V \\
              Q,K,V &\in \mathbb{R}^{n \times d_k}
            \end{align}
            ```

            **Why divide by $\sqrt{d_k}$?** For independent components with unit variance, $q\cdot k$ has variance $d_k$. Without scaling, large logits push softmax into saturated regions where gradients vanish.
          MD
          notes: "Walk through the shape: (n x d_k) @ (d_k x n) -> (n x n), softmax over keys, then times V (n x d_v)."
        },
        {
          type: "content", title: "Multi-head attention",
          body: <<~'MD',
            ## One attention is not enough

            Instead of a single attention over $d_{model}$ dimensions, run $h$ projections in parallel:

            $$\mathrm{head}_i = \mathrm{Attention}(QW_i^Q,\; KW_i^K,\; VW_i^V)$$

            $$\mathrm{MultiHead}(Q,K,V) = \mathrm{Concat}(\mathrm{head}_1, \dots, \mathrm{head}_h)\, W^O.$$

            ```latex
            \mathrm{MultiHead}(Q,K,V) = \mathrm{Concat}(\mathrm{head}_1,\dots,\mathrm{head}_h)W^O
            ```

            Different heads can specialise — one tracks syntax, another coreference, another position. With $h = 8$ and $d_{model} = 512$, each head has $d_k = d_v = 64$.
          MD
          notes: "Heads give the model multiple representation subspaces at the same cost."
        },
        {
          type: "content", title: "Positional encoding",
          body: <<~'MD',
            ## Attention is permutation-invariant

            Attention has no notion of order, so position is injected explicitly:

            $$PE_{(pos,\,2i)} = \sin\!\left(\frac{pos}{10000^{2i/d_{model}}}\right)$$

            $$PE_{(pos,\,2i+1)} = \cos\!\left(\frac{pos}{10000^{2i/d_{model}}}\right).$$

            ```latex
            PE_{(pos,2i)} = \sin\left(\frac{pos}{10000^{2i/d_{model}}}\right)
            ```

            The sinusoids form a geometric progression, so $PE_{pos+k}$ is a fixed linear function of $PE_{pos}$ — the model can learn **relative** offsets.
          MD
          notes: "Sinusoidal encodings let the model extrapolate to unseen lengths better than learned tables."
        },
        {
          type: "section", title: "Part II — The architecture", body: "Encoder, decoder, and the flow of tensors", theme: "dark",
          notes: "Now we can assemble the blocks."
        },
        {
          type: "content", title: "The encoder block",
          body: <<~'MD',
            ## Residual + LayerNorm around every sub-layer

            Each encoder layer is two sub-layers:

            $$\mathrm{LayerNorm}\big(x + \mathrm{MultiHead}(x,x,x)\big)$$
            $$\mathrm{LayerNorm}\big(z + \mathrm{FFN}(z)\big), \qquad \mathrm{FFN}(z) = W_2\,\mathrm{ReLU}(W_1 z + b_1) + b_2.$$

            The feed-forward network is applied **position-wise** — the same MLP to every token — and expands the width by $4\times$ before projecting back.
          MD
          notes: "Pre-LN vs post-LN matters for training stability at depth; the original paper is post-LN."
        },
        {
          type: "content", title: "The full architecture",
          body: <<~'MD',
            ## Encoder–decoder at a glance

            ```d2
            direction: right

            input: "Input tokens" { shape: document }
            embed: "Embedding + positional encoding"

            encoder: "Encoder × N" {
              mha: "Multi-head self-attention"
              ffn: "Feed-forward"
              mha -> ffn
            }

            decoder: "Decoder × N" {
              masked: "Masked self-attention"
              cross: "Cross-attention"
              ffn2: "Feed-forward"
              masked -> cross -> ffn2
            }

            output: "Output tokens"
            logits: "Linear + softmax"

            input -> embed -> encoder.mha
            encoder.ffn -> decoder.cross
            decoder.ffn2 -> logits -> output
            ```

            Each sub-layer is wrapped in a residual connection and layer norm: $\mathrm{LayerNorm}(x + \mathrm{Sublayer}(x))$.
          MD
          notes: "D2 renders with the TALA layout engine, so the graph stays legible as it grows."
        },
        {
          type: "content", title: "Decoder and causal masking",
          body: <<~'MD',
            ## You may not look ahead

            The decoder's first attention layer is **masked**: position $i$ may only attend to positions $\le i$. The mask is applied before the softmax:

            $$M_{ij} = \begin{cases} 0 & j \le i \\ -\infty & j > i \end{cases}, \qquad \mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}} + M\right).$$

            ```latex
            \mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}} + M\right),\quad M_{ij}=-\infty \text{ for } j>i
            ```

            This is what makes next-token prediction a valid training objective: every position predicts the future using only the past.
          MD
          notes: "The additive -inf mask becomes 0 after softmax, so future positions get exactly zero weight."
        },
        {
          type: "content", title: "Tensor shapes, step by step",
          body: <<~'MD',
            ## Follow the shapes

            ```d2
            direction: down

            tokens: "tokens (B, T)" { shape: oval }
            embed: "embeddings (B, T, d_model)"
            qkv: "Q, K, V (B, h, T, d_k)"
            scores: "scores (B, h, T, T)"
            weights: "softmax weights (B, h, T, T)" { shape: diamond }
            context: "context (B, h, T, d_k)"
            merged: "output (B, T, d_model)"

            tokens -> embed -> qkv -> scores -> weights -> context -> merged
            ```

            Memory is dominated by the $T \times T$ attention matrix: $O(B \cdot h \cdot T^2)$ floats. At $T = 4096$, $h = 16$ and fp16, that is already gigabytes.
          MD
          notes: "This is why FlashAttention and other IO-aware kernels matter — they avoid materialising the full T×T matrix."
        },
        {
          type: "content", title: "Reference implementation",
          body: <<~'MD',
            ## Scaled dot-product attention in PyTorch

            ```python
            import torch
            import torch.nn.functional as F

            def attention(q, k, v, mask=None):
                """q, k, v: (batch, heads, seq, d_k). Returns (context, weights)."""
                d_k = q.size(-1)
                scores = q @ k.transpose(-2, -1) / d_k ** 0.5   # (B, h, T, T)

                if mask is not None:
                    scores = scores.masked_fill(mask == 0, float("-inf"))

                weights = F.softmax(scores, dim=-1)             # rows sum to 1
                return weights @ v, weights                     # (B, h, T, d_k), (B, h, T, T)

            class MultiHead(torch.nn.Module):
                def __init__(self, d_model=512, heads=8):
                    super().__init__()
                    self.d_k, self.h = d_model // heads, heads
                    self.qkv = torch.nn.Linear(d_model, 3 * d_model)
                    self.out = torch.nn.Linear(d_model, d_model)

                def forward(self, x, mask=None):
                    b, t, _ = x.shape
                    q, k, v = self.qkv(x).chunk(3, dim=-1)
                    split = lambda z: z.view(b, t, self.h, self.d_k).transpose(1, 2)
                    ctx, _ = attention(split(q), split(k), split(v), mask)
                    ctx = ctx.transpose(1, 2).reshape(b, t, -1)
                    return self.out(ctx)
            ```
          MD
          notes: "This is the whole mechanism: three projections, a scaled product, a softmax, a weighted sum."
        },
        {
          type: "section", title: "Part III — Engineering at scale", body: "Cost, memory, kernels and scaling", theme: "dark",
          notes: "The architecture is simple; making it fast and cheap is the hard part."
        },
        {
          type: "content", title: "Complexity and engineering",
          body: <<~'MD',
            ## Cost per layer, and why attention won

            | Layer type | Complexity / layer | Sequential ops | Max path length |
            | --- | --- | --- | --- |
            | **Self-attention** | $O(n^2 \cdot d)$ | $O(1)$ | $O(1)$ |
            | Recurrent | $O(n \cdot d^2)$ | $O(n)$ | $O(n)$ |
            | Convolutional | $O(k \cdot n \cdot d^2)$ | $O(1)$ | $O(\log_k n)$ |

            Attention is more expensive per layer when $n > d$, but it is fully parallel and every token is one hop from every other.

            ```latex
            \text{Self-attention}: O(n^2 d) \qquad \text{Recurrent}: O(n d^2)
            ```
          MD
          notes: "The tradeoff: quadratic in sequence length, but O(1) sequential depth — which GPUs love."
        },
        {
          type: "content", title: "Inference and the KV cache",
          body: <<~'MD',
            ## Generation is memory-bound

            At inference we generate one token at a time. Recomputing all keys and values each step would be $O(n^2)$ per token, so we **cache** them:

            $$K_{\le t},\, V_{\le t} \in \mathbb{R}^{t \times d}.$$

            - Per token: $O(t \cdot d)$ attention work and $O(d)$ new cache.
            - Cache size: $2 \cdot L \cdot h \cdot d_k \cdot t$ floats per sequence.

            ```d2
            direction: right
            prompt: "Prompt tokens"
            prefill: "Prefill (parallel, compute-bound)" { shape: hexagon }
            cache: "KV cache" { shape: cylinder }
            decode: "Decode loop (1 token, memory-bound)"
            out: "Next token"

            prompt -> prefill -> cache -> decode -> out
            out -> decode: "append"
            ```
          MD
          notes: "Prefill is compute-bound and parallel; decode is memory-bandwidth-bound. This split drives most serving optimisations."
        },
        {
          type: "content", title: "IO-awareness: FlashAttention",
          body: <<~'MD',
            ## The bottleneck is memory traffic, not FLOPs

            Standard attention materialises the $n \times n$ score matrix in HBM, then reads it back for softmax — $O(n^2)$ memory traffic.

            FlashAttention tiles $Q, K, V$ into blocks and computes softmax **online**, keeping the running max and sum:

            $$m_{\text{new}} = \max(m_{\text{old}}, \max_j s_j), \qquad \ell_{\text{new}} = e^{m_{\text{old}} - m_{\text{new}}}\,\ell_{\text{old}} + \sum_j e^{s_j - m_{\text{new}}}.$$

            The result is **exact** attention with $O(n)$ memory and far less HBM traffic.
          MD
          notes: "This is the online-softmax trick: never store the full row, just the running max and normaliser."
        },
        {
          type: "content", title: "Training at scale",
          body: <<~'MD',
            ## What actually made it work

            - **Warmup + inverse-square-root schedule** on the learning rate:
              $$lrate = d_{model}^{-0.5} \cdot \min(step^{-0.5},\; step \cdot warmup^{-1.5}).$$
            - **Mixed precision** (bf16/fp16) with loss scaling for throughput.
            - **Parallelism**: data, tensor and pipeline parallelism across devices.
            - **Label smoothing** ($\epsilon_{ls} = 0.1$), **dropout** on residuals, attention and embeddings.

            ```python
            def lr(step, d_model=512, warmup=4000):
                return d_model ** -0.5 * min(step ** -0.5, step * warmup ** -1.5)
            ```
          MD
          notes: "None of these are exotic individually; together they made deep transformers trainable."
        },
        {
          type: "content", title: "Scaling laws",
          body: <<~'MD',
            ## Loss is a power law in compute, data and parameters

            Empirically, test loss falls predictably:

            $$L(N, D) \approx \left(\frac{N_c}{N}\right)^{\alpha} + \left(\frac{D_c}{D}\right)^{\beta},$$

            where $N$ is parameters and $D$ is training tokens. Chinchilla's lesson: for a fixed compute budget, scale $N$ and $D$ **together** — many models were undertrained.

            | Model | Parameters | Tokens |
            | --- | --- | --- |
            | GPT-3 | 175 B | 300 B |
            | Chinchilla | 70 B | 1.4 T |
            | LLaMA-2 70B | 70 B | 2 T |
          MD
          notes: "Chinchilla changed the field: most large models before it were too big for their data."
        },
        {
          type: "content", title: "Evaluation",
          body: <<~'MD',
            ## What we measure

            - **Perplexity** — $2^{-\frac{1}{N}\sum \log_2 p(w_i)}$; lower is better, but not comparable across tokenisers.
            - **Task metrics** — BLEU/ROUGE for translation and summarisation.
            - **Benchmarks** — GLUE/SuperGLUE, MMLU, HumanEval.
            - **Cost** — latency, throughput, memory per token.

            > Perplexity measures the model; benchmarks measure the product.
          MD
          notes: "Always report the tokeniser and the eval harness — numbers without them are not comparable."
        },
        {
          type: "content", title: "References",
          body: <<~'MD',
            ## Primary sources

            - Vaswani, A. et al. (2017). *Attention Is All You Need.* NeurIPS. arXiv:1706.03762.
            - Bahdanau, D., Cho, K., Bengio, Y. (2014). *Neural Machine Translation by Jointly Learning to Align and Translate.*
            - Dao, T. et al. (2022). *FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness.*
            - Hoffmann, J. et al. (2022). *Training Compute-Optimal Large Language Models.* (Chinchilla)
            - Radford, A. et al. (2018). *Improving Language Understanding by Generative Pre-Training.*
          MD
          notes: "Point people at the original paper first, then FlashAttention for the systems story and Chinchilla for scaling."
        }
      ]
    end
  end
end
