# Contributing to Writebook

## Cutting a Release

To cut a release run `bin/release <version>` from the exact commit you want to release.

The script will create an annotated git tag, build a multi-arch Docker image,
push it to the ONCE docker registry, generate a ZIP bundle of the current repo
and upload that to the ONCE server too.

> [!IMPORTANT]
> You'll have to have Docker installed with buildx enabled, and you have to have access to the ONCE servers and registry.

> [!WARNING]
> Because the release script builds a multi-arch Docker container it can take a very long time
> to complete on the first run. On subsequent runs it will be able to re-use the cached layers
> and will be much faster.

GitHub will build and push multi-arch Docker images to GHCR automatically for every tagged release - `bin/release` creates a tagged release, so there is nothing else you need to do after you run it.

### Release notes

The release script will, by default, auto-generate release notes for you based on the git commit history.

If you'd like to write your own release notes you can pass `--notes` when calling the command. This will
start your editor of choice *(whatever is set in `$EDITOR`)* and let you write your own release notes.
The script will then use those notes instead of auto-generating them.
