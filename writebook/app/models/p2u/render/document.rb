require "erb"

module P2u
  module Render
    # Builds a single self-contained HTML document for a deck: 16:9 slides,
    # keyboard/click navigation, progress, speaker notes and print styles (so
    # "Save as PDF" yields one landscape page per slide). Diagram and equation
    # SVGs are inlined; only KaTeX is loaded from a CDN.
    class Document
      PALETTES = {
        # Notion-flavored palettes: warm ink, white/charcoal paper, Notion accents.
        "writebook" => { bg: "#ffffff", fg: "#37352f", accent: "#2383e2", subtle: "#e9e9e7", page: "#f7f7f5" },
        "black" => { bg: "#191919", fg: "#f2f2f2", accent: "#529cca", subtle: "#2f2f2f", page: "#111111" },
        "blue" => { bg: "#191919", fg: "#eef4fb", accent: "#529cca", subtle: "#2f2f2f", page: "#111111" },
        "green" => { bg: "#191919", fg: "#eefaf2", accent: "#5fa56a", subtle: "#2f2f2f", page: "#111111" },
        "magenta" => { bg: "#191919", fg: "#fdeef5", accent: "#c14c8a", subtle: "#2f2f2f", page: "#111111" },
        "orange" => { bg: "#191919", fg: "#fff3e6", accent: "#d9730d", subtle: "#2f2f2f", page: "#111111" },
        "violet" => { bg: "#191919", fg: "#f2efff", accent: "#9065b0", subtle: "#2f2f2f", page: "#111111" },
        "white" => { bg: "#f7f7f5", fg: "#37352f", accent: "#2383e2", subtle: "#e9e9e7", page: "#ffffff" }
      }.freeze

      def initialize(deck:, slides:, title: nil)
        @deck = P2u.deep_stringify(deck || {})
        @slides = slides
        @title = title.presence || @deck["title"].presence || "Untitled deck"
      end

      def theme
        name = @deck["theme"].is_a?(Hash) ? @deck["theme"]["preset"] : @deck["theme"]
        PALETTES[name.to_s] ? name.to_s : "writebook"
      end

      def dark? = !%w[writebook white].include?(theme)

      # A "scroll" deck is not locked to the 16:9 frame: every slide flows down
      # the page and the reader scrolls, so long slides are never clipped.
      def scroll? = ActiveModel::Type::Boolean.new.cast(@deck["scroll"] || @deck["flow"])

      def highlight_css
        base = "https://cdn.jsdelivr.net/npm/highlight.js@11.10.0/styles"
        dark? ? "#{base}/github-dark.min.css" : "#{base}/github.min.css"
      end

      def to_html
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{h(@title)}</title>
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" crossorigin="anonymous">
          <link rel="stylesheet" href="#{highlight_css}" crossorigin="anonymous">
          <style>#{styles}</style>
          </head>
          <body class="p2u theme--#{theme}#{' p2u-scroll' if scroll?}">
          <main class="p2u-deck" data-p2u-deck>
          #{inline_rendered_svgs(slide_markup)}
          </main>
          <div class="p2u-progress" data-p2u-progress></div>
          <div class="p2u-hud">
            <button type="button" data-p2u-prev aria-label="Previous slide">‹</button>
            <span data-p2u-counter>1 / #{@slides.size}</span>
            <button type="button" data-p2u-next aria-label="Next slide">›</button>
            <button type="button" data-p2u-notes aria-label="Speaker notes (N)">notes</button>
          </div>
          <aside class="p2u-notes-panel" data-p2u-notes-panel hidden></aside>
          <script>#{javascript}</script>
          <script type="module">#{markdown_module}</script>
          </body>
          </html>
        HTML
      end

      private
      # Replace references to content-addressed render assets with the SVG
      # markup itself, so the exported file is genuinely self-contained and
      # readable without JavaScript.
      RENDERED_IMG_SRC = %r{<img src="/rendered/([a-f0-9]{64})\.svg"[^>]*>}m

      def inline_rendered_svgs(html)
        html.gsub(RENDERED_IMG_SRC) do
          filename = "#{Regexp.last_match(1)}.svg"
          file = RenderedAsset.file_for(filename)
          next Regexp.last_match(0) unless file&.exist?

          file.read.sub(/\A<\?xml[^>]*\?>\s*/, "")
        end
      end

      def slide_markup
          @slides.each_with_index.map do |slide, index|
            notes = slide[:notes].to_s
            <<~SLIDE
              <section class="p2u-slide p2u-layout--#{h(slide[:layout])}" data-index="#{index}" data-notes="#{h(notes)}">
                #{slide[:kicker].present? ? %(<span class="p2u-kicker">#{h(slide[:kicker])}</span>) : ''}
                #{slide[:html]}
                <span class="p2u-slide__number">#{index + 1} / #{@slides.size}</span>
              </section>
            SLIDE
          end.join
        end

        def styles
          <<~CSS
            *, *::before, *::after { box-sizing: border-box; }
            :root {
              --p2u-bg: #{palette[:bg]};
              --p2u-fg: #{palette[:fg]};
              --p2u-accent: #{palette[:accent]};
              --p2u-subtle: #{palette[:subtle]};
              --p2u-page: #{palette[:page] || '#0b0b10'};
            }
            html, body { margin: 0; height: 100%; }
            body.p2u {
              background: var(--p2u-page);
              color: var(--p2u-fg);
              font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              overflow: hidden;
            }
            .p2u-deck { align-items: center; display: flex; height: 100vh; justify-content: center; width: 100vw; }
            .p2u-slide {
              aspect-ratio: 16 / 9;
              background: var(--p2u-bg);
              border-radius: 8px;
              box-shadow: 0 8px 32px rgba(0,0,0,.35);
              container-type: inline-size;
              display: none;
              flex-direction: column;
              inline-size: min(96vw, 170vh);
              justify-content: center;
              max-block-size: 94vh;
              overflow-x: hidden;
              overflow-y: auto;
              overscroll-behavior: contain;
              padding: clamp(1.5rem, 5cqi, 4.5rem);
              position: relative;
              text-align: start;
            }
            .p2u-slide.is-active { display: flex; }
            /* Flowing reading mode: every slide stacks and the page scrolls. */
            body.p2u-scroll { block-size: auto; overflow: auto; }
            .p2u-scroll .p2u-deck { display: block; block-size: auto; padding: clamp(1rem, 3vw, 2.5rem) 0; }
            .p2u-scroll .p2u-slide {
              aspect-ratio: auto;
              display: flex;
              inline-size: min(96vw, 1080px);
              margin: 0 auto clamp(1.5rem, 4vw, 3rem);
              max-block-size: none;
              overflow: visible;
            }
            .p2u-scroll .p2u-slide__inner { overflow: visible; }
            .p2u-scroll .p2u-hud, .p2u-scroll .p2u-progress { display: none; }
            .p2u-slide__inner { display: flex; flex-direction: column; gap: 1em; min-block-size: 0; }
            .p2u-slide__inner--content, .p2u-slide__inner--diagram, .p2u-slide__inner--equation,
            .p2u-slide__inner--full-code, .p2u-slide__inner--table, .p2u-slide__inner--code-split,
            .p2u-slide__inner--recap, .p2u-slide__inner--qa, .p2u-slide__inner--references,
            .p2u-slide__inner--two-column, .p2u-slide__inner--compare, .p2u-slide__inner--metric-row,
            .p2u-slide__inner--image, .p2u-slide__inner--image-grid, .p2u-slide__inner--quote {
              justify-content: flex-start;
              overflow: auto;
            }
            .p2u-slide__inner--diagram, .p2u-slide__inner--equation { justify-content: center; overflow: hidden; }
            .p2u-kicker {
              color: var(--p2u-accent); font-size: clamp(.7rem, 1.6cqi, 1rem); font-weight: 600;
              letter-spacing: .08em; margin-block-end: .4rem; text-transform: uppercase;
            }
            .p2u-slide__number { bottom: 1.1rem; color: color-mix(in srgb, var(--p2u-fg) 45%, transparent); font-size: .8rem; position: absolute; right: 1.4rem; }
            .p2u-heading { font-size: clamp(1.5rem, 4.4cqi, 3rem); font-weight: 600; letter-spacing: -.01em; line-height: 1.2; margin: 0; }
            .p2u-title { font-size: clamp(2.2rem, 9cqi, 6rem); font-weight: 600; letter-spacing: -.02em; line-height: 1.05; margin: 0; }
            .p2u-subtitle { color: color-mix(in srgb, var(--p2u-fg) 72%, transparent); font-size: clamp(1.1rem, 3.4cqi, 2.2rem); margin: 0; }
            .p2u-slide__inner--title, .p2u-slide__inner--section { align-items: center; justify-content: center; text-align: center; }
            .p2u-slide__inner--title .p2u-title, .p2u-slide__inner--section .p2u-title { color: var(--p2u-fg); }
            .p2u-slide__inner--section .p2u-title { color: var(--p2u-fg); }
            .p2u-slide :is(p, li) { font-size: clamp(.95rem, 2.3cqi, 1.6rem); line-height: 1.5; }
            .p2u-slide :is(h1,h2,h3) { line-height: 1.15; }
            .p2u-slide a { color: var(--p2u-accent); }
            .p2u-slide img { border-radius: 6px; max-inline-size: 100%; }
            .p2u-slide table { border-collapse: collapse; font-size: clamp(.8rem, 2cqi, 1.25rem); inline-size: 100%; }
            .p2u-slide th, .p2u-slide td { border-bottom: 1px solid var(--p2u-subtle); padding: .5em .7em; text-align: start; }
            .p2u-slide pre { background: color-mix(in srgb, var(--p2u-fg) 7%, transparent); border: 1px solid var(--p2u-subtle); border-radius: 6px; font-size: clamp(.7rem, 1.8cqi, 1.05rem); overflow: auto; padding: 1em 1.2em; }
            .p2u-slide code { font-family: "SF Mono", ui-monospace, Menlo, Consolas, monospace; }
            .p2u-slide :not(pre) > code { background: var(--p2u-subtle); border-radius: 4px; padding: .1em .35em; }
            .p2u-columns { align-items: start; display: grid; gap: clamp(1rem, 3cqi, 2.5rem); min-block-size: 0; }
            .p2u-columns--two-column, .p2u-columns--compare { grid-template-columns: 1fr 1fr; }
            .p2u-columns--code-split { grid-template-columns: 1.15fr .85fr; }
            .p2u-columns--compare .p2u-column { background: color-mix(in srgb, var(--p2u-fg) 4%, transparent); border-radius: 8px; padding: 1em; }
            .p2u-column { min-block-size: 0; min-inline-size: 0; }
            .p2u-column > :first-child { margin-block-start: 0; }
            .p2u-column > :last-child { margin-block-end: 0; }
            .p2u-metrics { display: grid; gap: clamp(.75rem, 2.5cqi, 1.75rem); grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); }
            .p2u-metric { background: color-mix(in srgb, var(--p2u-fg) 4%, transparent); border: 1px solid var(--p2u-subtle); border-radius: 8px; display: flex; flex-direction: column; gap: .3em; padding: 1.1em 1.3em; }
            .p2u-metric__value { font-size: clamp(1.6rem, 5cqi, 3.2rem); font-weight: 600; letter-spacing: -.01em; }
            .p2u-metric__label { color: color-mix(in srgb, var(--p2u-fg) 68%, transparent); font-size: clamp(.75rem, 1.9cqi, 1.1rem); }
            .p2u-quote { border-inline-start: 3px solid var(--p2u-accent); margin: 0; padding-inline-start: 1.1em; }
            .p2u-quote p { font-size: clamp(1.3rem, 4cqi, 2.6rem) !important; font-weight: 500; line-height: 1.25; margin: 0; }
            .p2u-quote cite { color: color-mix(in srgb, var(--p2u-fg) 65%, transparent); display: block; font-size: clamp(.85rem, 2cqi, 1.2rem); margin-block-start: .6em; }
            .p2u-diagram, .p2u-equation { align-items: center; color: var(--p2u-fg); display: flex; justify-content: center; min-block-size: 0; }
            .p2u-diagram svg, .p2u-equation svg { block-size: auto; max-block-size: 100%; max-inline-size: 100%; }
            .p2u-equation svg { max-block-size: 40vh; }
            .p2u-diagram svg { max-block-size: 58vh; }
            .p2u-diagram--sketch {
              border: 2px solid color-mix(in srgb, var(--p2u-fg) 28%, transparent);
              border-radius: 18px 8px 16px 10px / 10px 16px 8px 18px;
              padding: clamp(.5rem, 2cqi, 1.25rem);
            }
            .p2u-diagram--sketch svg { max-block-size: 52vh; }
            .p2u-slide__inner--typst { justify-content: center; overflow: hidden; }
            .p2u-typst { align-items: center; color: var(--p2u-fg); display: flex; justify-content: center; min-block-size: 0; }
            .p2u-typst svg { block-size: auto; max-block-size: 100%; max-inline-size: 100%; }
            .p2u-images--image-grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); }
            .p2u-images figure { margin: 0; }
            .p2u-images figcaption { color: color-mix(in srgb, var(--p2u-fg) 62%, transparent); font-size: .85rem; margin-block-start: .4em; }
            .p2u-callout { background: color-mix(in srgb, var(--p2u-fg) 5%, transparent); border-inline-start: 3px solid var(--p2u-accent); border-radius: 6px; padding: .8em 1em; }
            .p2u-definition { margin: 0; } .p2u-definition dt { font-weight: 600; } .p2u-definition dd { margin: .2em 0 0; }
            .p2u-error { color: #ff9a9a; }
            .p2u-progress { background: var(--p2u-accent); block-size: 3px; inline-size: 0; left: 0; position: fixed; top: 0; transition: inline-size .2s ease; z-index: 30; }
            .p2u-hud { align-items: center; bottom: 1rem; display: flex; gap: .5rem; left: 50%; position: fixed; transform: translateX(-50%); z-index: 30; }
            .p2u-hud button, .p2u-hud span { background: color-mix(in srgb, var(--p2u-fg) 10%, transparent); border: 1px solid color-mix(in srgb, var(--p2u-fg) 20%, transparent); border-radius: 4px; color: var(--p2u-fg); cursor: pointer; font: inherit; font-size: .85rem; min-inline-size: 2.4rem; padding: .45rem .8rem; }
            .p2u-hud button:hover { background: color-mix(in srgb, var(--p2u-fg) 18%, transparent); }
            .p2u-notes-panel { background: var(--p2u-bg); border-block-start: 1px solid var(--p2u-subtle); bottom: 0; color: var(--p2u-fg); font-size: 1rem; left: 0; line-height: 1.5; max-block-size: 34vh; overflow: auto; padding: 1.2rem 1.5rem; position: fixed; right: 0; white-space: pre-wrap; z-index: 40; }
            @media print {
              @page { margin: 0; size: 297mm 167mm; }
              html, body { height: auto; overflow: visible; }
              body.p2u { background: #fff; }
              .p2u-deck { display: block; height: auto; }
              .p2u-slide { aspect-ratio: auto; border-radius: 0; box-shadow: none; display: flex !important; inline-size: 100%; min-block-size: 167mm; page-break-after: always; }
              .p2u-hud, .p2u-progress, .p2u-notes-panel { display: none !important; }
            }
          CSS
        end

        def javascript
          <<~JS
            (function () {
              var slides = Array.prototype.slice.call(document.querySelectorAll('.p2u-slide'));
              if (!slides.length) return;
              var index = 0;
              var counter = document.querySelector('[data-p2u-counter]');
              var progress = document.querySelector('[data-p2u-progress]');
              var notesPanel = document.querySelector('[data-p2u-notes-panel]');

              function render() {
                slides.forEach(function (slide, i) { slide.classList.toggle('is-active', i === index); });
                if (counter) counter.textContent = (index + 1) + ' / ' + slides.length;
                if (progress) progress.style.inlineSize = ((index + 1) / slides.length * 100) + '%';
                if (notesPanel) notesPanel.textContent = slides[index].dataset.notes || 'No speaker notes for this slide.';
              }
              function go(n) { index = Math.max(0, Math.min(slides.length - 1, n)); render(); }
              function next() { go(index + 1); }
              function prev() { go(index - 1); }

              document.querySelector('[data-p2u-next]').addEventListener('click', next);
              document.querySelector('[data-p2u-prev]').addEventListener('click', prev);
              document.querySelector('[data-p2u-notes]').addEventListener('click', function () {
                if (notesPanel) notesPanel.hidden = !notesPanel.hidden;
              });

              document.addEventListener('keydown', function (event) {
                if (event.target.closest('input, textarea, select')) return;
                switch (event.key) {
                  case 'ArrowRight': case ' ': case 'PageDown': case 'Enter': event.preventDefault(); next(); break;
                  case 'ArrowLeft': case 'PageUp': event.preventDefault(); prev(); break;
                  case 'Home': event.preventDefault(); go(0); break;
                  case 'End': event.preventDefault(); go(slides.length - 1); break;
                  case 'f': case 'F':
                    if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen && document.documentElement.requestFullscreen();
                    break;
                  case 'n': case 'N': if (notesPanel) notesPanel.hidden = !notesPanel.hidden; break;
                  case 'Escape': if (notesPanel) notesPanel.hidden = true; break;
                }
              });
              document.addEventListener('click', function (event) {
                if (event.target.closest('.p2u-hud, .p2u-notes-panel, a, button')) return;
                (event.clientX / window.innerWidth > 0.5 ? next : prev)();
              });

              render();
            })();
          JS
        end

        # Standalone decks render Markdown in the browser with markdown-it and
        # its plugins: KaTeX for $...$ / $$...$$ math and highlight.js for code.
        def markdown_module
          <<~JS
            import MarkdownIt from 'https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/+esm';
            import katex from 'https://cdn.jsdelivr.net/npm/katex@0.16.11/+esm';
            import texmath from 'https://cdn.jsdelivr.net/npm/markdown-it-texmath@1.0.0/+esm';
            import renderMathInElement from 'https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.mjs';
            import hljs from 'https://cdn.jsdelivr.net/npm/highlight.js@11.10.0/+esm';

            const md = new MarkdownIt({ html: true, linkify: true, breaks: false });
            md.use(texmath, { engine: katex, delimiters: 'dollars', katexOptions: { throwOnError: false } });
            md.options.highlight = function (source, language) {
              if (language && hljs.getLanguage(language)) {
                try {
                  return '<pre class="hljs"><code>' + hljs.highlight(source, { language: language, ignoreIllegals: true }).value + '</code></pre>';
                } catch (error) {}
              }
              return '<pre class="hljs"><code>' + md.utils.escapeHtml(source) + '</code></pre>';
            };

            function renderMarkdown() {
              document.querySelectorAll('.p2u-md').forEach(function (container) {
                if (container.dataset.rendered) return;
                var assets = {};
                try { assets = JSON.parse(container.dataset.assets || '{}'); } catch (error) {}
                var html = md.render(container.textContent);
                Object.keys(assets).forEach(function (token) {
                  var block = assets[token];
                  html = html.replace(new RegExp('<p>\\s*' + token + '\\s*</p>', 'g'), block);
                  html = html.split(token).join(block);
                });
                container.innerHTML = html;
                container.dataset.rendered = '1';
              });
              renderMathInElement(document.body, {
                delimiters: [
                  { left: '$$', right: '$$', display: true },
                  { left: '$', right: '$', display: false },
                  { left: '\\\\(', right: '\\\\)', display: false },
                  { left: '\\\\[', right: '\\\\]', display: true }
                ],
                throwOnError: false
              });
            }

            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', renderMarkdown);
            } else {
              renderMarkdown();
            }
          JS
        end

        def palette = PALETTES.fetch(theme, PALETTES["violet"])
        def h(value) = ERB::Util.html_escape(value.to_s)
    end
  end
end
