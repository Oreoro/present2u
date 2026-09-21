# Present2u render container — d2 + typst + pdflatex/pdftocairo + headless Chrome.
#
# Build:
#   docker build -t present2u-renderer container/
# Run:
#   docker run -p 8080:8080 present2u-renderer
#
# Cloudflare Containers builds this image from wrangler.jsonc (containers[].image).

FROM node:22-bookworm-slim

ARG D2_VERSION=0.6.7
ARG TYPST_VERSION=0.12.0
ENV DEBIAN_FRONTEND=noninteractive \
    PORT=8080

# Runtime deps: TeX (pdflatex), poppler (pdftocairo), fonts.
# No Chromium: PDF export is served by Cloudflare Browser Rendering, keeping the
# image small so container cold starts fit the Durable Object's startup window.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils \
      texlive-latex-base texlive-latex-recommended \
      texlive-fonts-recommended \
      poppler-utils \
      fonts-dejavu fontconfig \
    && rm -rf /var/lib/apt/lists/*

# D2 (TALA layout engine) — install the prebuilt binary directly (no make).
RUN curl -fsSL "https://github.com/d2lang/d2/releases/download/v${D2_VERSION}/d2-v${D2_VERSION}-linux-amd64.tar.gz" \
      -o /tmp/d2.tar.gz \
    && tar -xzf /tmp/d2.tar.gz -C /tmp \
    && install -m 0755 "/tmp/d2-v${D2_VERSION}/bin/d2" /usr/local/bin/d2 \
    && rm -rf /tmp/d2*

# Typst.
RUN curl -fsSL "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-x86_64-unknown-linux-musl.tar.xz" \
      -o /tmp/typst.tar.xz \
    && tar -xJf /tmp/typst.tar.xz -C /tmp \
    && mv /tmp/typst-x86_64-unknown-linux-musl/typst /usr/local/bin/typst \
    && rm -rf /tmp/typst*

WORKDIR /app
COPY package.json ./
COPY server.mjs ./

EXPOSE 8080
CMD ["node", "server.mjs"]