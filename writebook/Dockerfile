# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.7
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"


# Throw-away build stage to reduce size of final image
FROM --platform=$TARGETPLATFORM base as build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev libvips pkg-config

# Install application gems
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libsqlite3-0 libvips redis \
      xz-utils poppler-utils \
      texlive-latex-base texlive-latex-recommended texlive-fonts-recommended \
      fonts-dejavu fonts-liberation && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Rendering toolchain: D2 (TALA) and Typst. pdflatex + pdftocairo come from
# texlive/poppler above. ARCH is the build target (amd64 or arm64).
ARG TARGETARCH
RUN set -eux; \
    d2arch=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64); \
    typstarch=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64); \
    curl -fsSL "https://github.com/terrastruct/d2/releases/download/v0.9.0/d2-v0.9.0-linux-${d2arch}.tar.gz" -o /tmp/d2.tgz; \
    tar -xzf /tmp/d2.tgz -C /tmp; \
    install -m 0755 /tmp/d2-v0.9.0/bin/d2 /usr/local/bin/d2; \
    curl -fsSL "https://github.com/typst/typst/releases/download/v0.15.1/typst-${typstarch}-unknown-linux-musl.tar.xz" -o /tmp/typst.tar.xz; \
    tar -xJf /tmp/typst.tar.xz -C /tmp; \
    install -m 0755 "/tmp/typst-${typstarch}-unknown-linux-musl/typst" /usr/local/bin/typst; \
    rm -rf /tmp/d2.tgz /tmp/d2-v0.9.0 /tmp/typst.tar.xz "/tmp/typst-${typstarch}-unknown-linux-musl"; \
    d2 --version; typst --version; pdflatex --version | head -1; pdftocairo -v 2>&1 | head -1

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Set version and revision
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION
ARG GIT_REVISION
ENV GIT_REVISION=$GIT_REVISION

# Entrypoint prepares the application.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 80 443
CMD ["bin/boot"]
