FROM lbjlaq/antigravity-manager:latest

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar jq \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /app/start.sh
RUN chmod 0755 /app/start.sh

ENTRYPOINT ["/app/start.sh"]
