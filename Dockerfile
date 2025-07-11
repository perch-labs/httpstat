FROM python:3.11-slim

# Install runtime dependencies including curl and jq
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the patched build folder and install
COPY patch-build/ ./
RUN pip install .

# Copy batch script
COPY httpstat-batch.sh /usr/local/bin/httpstat-batch.sh
RUN chmod +x /usr/local/bin/httpstat-batch.sh

# Create data directory
RUN mkdir -p /data
WORKDIR /data

ENTRYPOINT ["httpstat-batch.sh"]
CMD ["-h"]