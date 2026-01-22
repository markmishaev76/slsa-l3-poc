# Simple test container for SLSA L3 experimentation
FROM alpine:3.19

LABEL org.opencontainers.image.title="SLSA L3 Test"
LABEL org.opencontainers.image.description="Test container for SLSA Build Level 3 experimentation"
LABEL org.opencontainers.image.source="https://github.com/slsa-l3-poc"

RUN apk add --no-cache curl jq

COPY scripts/ /app/scripts/
COPY README.md /app/

WORKDIR /app

CMD ["echo", "SLSA L3 PoC Container"]
