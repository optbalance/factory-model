# toolchain.Containerfile: the image the product builds and tests in.
# The factory builds it from main, with the repo root as build context, and adds its layers on top.
FROM docker.io/library/node:22-bookworm-slim
# + system packages the build or tests need, for example:
# RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
#  && rm -rf /var/lib/apt/lists/*
# + if the build tool downloads dependencies outside the worktree (Gradle, Maven, Cargo, Go…):
#   point its cache at a fixed path with ENV and pre-fetch everything main declares into it.
#   Node needs neither: node_modules is in the worktree.
