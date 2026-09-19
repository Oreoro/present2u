module DeckTemplates
  # The reference physics derivation deck: KaTeX math, a server-compiled LaTeX
  # block, D2 + sketch diagrams, highlighted code and a context.dev figure.
  class Einstein
    def self.title = "E = mc² — scientific derivation"

    def self.description = "Mass–energy equivalence derived from special relativity, with LaTeX, D2 and code."

    def self.manifest
      {
        deck: {
          title: "E = mc²",
          subtitle: "Mass–energy equivalence, derived and explained",
          author: "Present2u",
          theme: "black",
          slides: slides
        }
      }
    end

    def self.slides
      [
        {
          type: "section", title: "E = mc²", body: "Mass–energy equivalence", theme: "dark",
          notes: "Set the stage: this is the most famous equation in physics, and it falls out of special relativity."
        },
        {
          type: "section", title: "Special Relativity", body: "1905 · Annus Mirabilis",
          notes: "Two postulates: physics is the same in all inertial frames, and the speed of light is invariant."
        },
        {
          type: "content", title: "The Postulates",
          body: <<~'MD',
            ## Two postulates

            - **Principle of relativity** — the laws of physics are identical in every inertial frame.
            - **Invariant light speed** — $c = 299\,792\,458\ \text{m}\,\text{s}^{-1}$ in vacuum, for every observer.

            Time and length are no longer absolute. The Lorentz factor

            $$\gamma = \frac{1}{\sqrt{1 - v^2/c^2}}$$

            measures how much they stretch.
          MD
          notes: "Emphasise that c being invariant forces time dilation and length contraction."
        },
        {
          type: "content", title: "Deriving E = mc²",
          body: <<~'MD',
            ## From the relativistic energy–momentum relation

            The full relation is $E^2 = (pc)^2 + (m_0 c^2)^2$. For a body at rest, $p = 0$, so

            ```latex
            \begin{align}
              E^2 &= (pc)^2 + (m_0 c^2)^2 \\
              E   &= \gamma m_0 c^2 \\
              \gamma &= \frac{1}{\sqrt{1 - v^2/c^2}}
            \end{align}
            ```

            Setting $v = 0$ gives $\gamma = 1$ and therefore

            $$E = m_0 c^2.$$
          MD
          notes: "The LaTeX block is compiled server-side with pdflatex and served as an SVG."
        },
        {
          type: "content", title: "What it means",
          body: <<~'MD',
            ## Mass is frozen energy

            A mass $m$ carries rest energy

            $$E_0 = mc^2.$$

            | Quantity | Symbol | Value |
            | --- | --- | --- |
            | Speed of light | $c$ | $2.998 \times 10^8\ \text{m/s}$ |
            | 1 gram of matter | $E_0$ | $8.99 \times 10^{13}\ \text{J}$ |
            | TNT equivalent | — | $\approx 21.5\ \text{kt}$ |

            One gram is roughly the yield of the bomb dropped on Nagasaki.
          MD
          notes: "Concrete anchor: a gram of matter is ~21 kilotons of TNT."
        },
        {
          type: "content", title: "Worked example in code",
          body: <<~'MD',
            ## Compute it in Python

            ```python
            C = 299_792_458            # m/s, exact by definition

            def rest_energy(mass_kg):
                """Rest energy in joules for a mass in kilograms."""
                return mass_kg * C ** 2

            rest_energy(1.0)           # 1 kg  -> 8.987551787368176e+16 J
            rest_energy(1e-3)          # 1 g   -> 8.987551787368176e+13 J
            rest_energy(1e-3) / 4.184e12   # kilotons of TNT -> 21.48
            ```

            The units are the whole story: $c^2$ is a conversion factor between mass and energy, not a suggestion.
          MD
          notes: "Code blocks are natively highlighted with Rouge — no extra tooling."
        },
        {
          type: "content", title: "Relativistic energy–momentum",
          body: <<~'MD',
            ## The full relation

            $$E^2 = (pc)^2 + (m_0 c^2)^2$$

            Special cases:

            - **At rest** ($p = 0$): $E = m_0 c^2$.
            - **Massless** ($m_0 = 0$): $E = pc$, the photon.
            - **Ultra-relativistic** ($pc \gg m_0c^2$): $E \approx pc$.

            ```latex
            E = \sqrt{(pc)^2 + (m_0 c^2)^2}
            ```
          MD
          notes: "This is the equation that generalises E = mc² to moving bodies."
        },
        {
          type: "content", title: "Mass–energy in the nucleus",
          body: <<~'MD',
            ## Fission releases binding energy

            The products weigh less than the reactants. The missing mass appears as kinetic energy.

            ```d2
            direction: right

            neutron: n
            u235: "²³⁵U"
            ba: "¹⁴¹Ba"
            kr: "⁹²Kr"
            energy: "ΔE = Δm · c²" {
              shape: cloud
              style.fill: "#fff3bf"
            }

            neutron -> u235
            u235 -> ba
            u235 -> kr
            u235 -> neutron: "+2n"
            u235 -> energy: "≈ 200 MeV"
            ```

            Each fission of $^{235}\text{U}$ releases about $200\ \text{MeV} \approx 3.2 \times 10^{-11}\ \text{J}$.
          MD
          notes: "D2 with the TALA layout engine keeps the graph readable automatically."
        },
        {
          type: "content", title: "Binding energy curve (sketch)", sketch: true,
          body: <<~'MD',
            ## Why fusion and fission both release energy

            ```d2-sketch
            direction: down
            peak: "⁵⁶Fe — most tightly bound" { shape: diamond }
            fusion: "Fusion: H → He"
            fission: "Fission: U → Ba + Kr"
            peak -> fusion: "releases"
            peak -> fission: "releases"
            ```

            Nuclei climb toward iron, releasing energy on the way. This slide uses **sketch mode**:
            a hand-drawn typeface and wobbly geometry, ideal for whiteboarding an idea.
          MD
          notes: "Sketch mode = hand-drawn aesthetic + D2 --sketch diagrams. Great for intuition."
        },
        {
          type: "content", title: "Order-of-magnitude sanity checks",
          body: <<~'MD',
            ## Fermi estimates

            | Process | Energy scale |
            | --- | --- |
            | Chemical bond | $1\ \text{eV}$ |
            | Nuclear binding | $1\ \text{MeV}$ |
            | Electron rest mass | $0.511\ \text{MeV}$ |
            | Proton rest mass | $938\ \text{MeV}$ |

            So nuclear reactions tap roughly a **million times** more energy per atom than chemistry — because $c^2$ is enormous.
          MD
          notes: "The factor of ~10^6 between chemistry and nuclear physics is why c² matters."
        },
        {
          type: "content", title: "References",
          body: <<~'MD',
            ## Further reading

            - Einstein, A. (1905). *Ist die Trägheit eines Körpers von seinem Energieinhalt abhängig?* Annalen der Physik.
            - Einstein, A. (1905). *Zur Elektrodynamik bewegter Körper.*
            - Griffiths, D. J. *Introduction to Electrodynamics*, ch. 12.
            - NIST CODATA value of $c$: exact, $299\,792\,458\ \text{m}\,\text{s}^{-1}$.

            > Everything should be made as simple as possible, but not simpler.
          MD
          notes: "Close on the primary sources."
        }
      ]
    end
  end
end
