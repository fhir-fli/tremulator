# Toy client/server for the adversary-harness mutation test.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends tcpdump && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir cryptography==43.0.3
WORKDIR /toy
COPY server.py client.py ./
