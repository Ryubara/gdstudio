# The game server: headless Godot running `NetServer` (game/gameplay/net/net_server.gd) on a WebSocket.
# Build context: a folder with this Dockerfile, railway.toml and the Godot project at game/; server/stage.sh makes it.
#   server/stage.sh <folder> && docker build -t game-server <folder>
#   docker run --rm -e PORT=8910 -p 8910:8910 game-server
# Railway sets $PORT and ends TLS at its edge (clients use wss://), so the server speaks plain ws:// inside.
FROM debian:bookworm-slim AS godot

# The Godot version and the SHA-512 of its linux-x64 zip are the ones the GDStudio kit pins in tools.toml
# (kit test: python/tests/test_server_image.py). Change them only with the kit's pin.
ARG GODOT_VERSION=4.7.2
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
    && unzip -q /tmp/godot.zip -d /opt \
    && mv "/opt/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /opt/godot \
    && rm /tmp/godot.zip

FROM debian:bookworm-slim
# tini is process 1: it hands the platform's SIGTERM to Godot and reaps, so a stop is a clean quit, not a kill.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libfontconfig1 tini \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 game
COPY --from=godot /opt/godot /usr/local/bin/godot
# /app must belong to the game user: Godot writes its import cache (.godot/) inside the project folder.
RUN mkdir /app && chown game:game /app
WORKDIR /app
USER game
COPY --chown=game:game game /app
# Godot's worker pool has a thread a core by default, and Jolt hands every physics step to all of them: an idle server
# took a quarter of a core on a 16-core host. Two threads keep the step times and idle near 2% (override.cfg is read
# over project.godot; the client's builds never see it). Kit docs: engines/godot/multiplayer.md#headless-server-image.
ARG WORKER_THREADS=2
RUN printf '\n[threading]\nworker_pool/max_threads=%s\n' "$WORKER_THREADS" >> /app/override.cfg
# Import once at build time so the container starts without a first-run import.
RUN godot --headless --path /app --import
ENV PORT=8910
EXPOSE 8910
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]
