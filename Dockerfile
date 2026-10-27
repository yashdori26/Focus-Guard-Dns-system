# ==============================================================================
# FocusDNS High-Performance Hardened Backend & Resolver Container
# ==============================================================================
FROM python:3.12-slim AS runtime

# Set environment
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DNS_HOST="0.0.0.0" \
    DNS_PORT=53 \
    HTTP_PORT=8080

WORKDIR /app

# Install minimal runtime dependencies and security updates
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcap2-bin \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install python requirements
COPY server/requirements.txt /app/server/requirements.txt
RUN pip install --no-cache-dir -r /app/server/requirements.txt

# Copy backend application code
COPY server/ /app/server/

# Grant python permission to bind to low ports (port 53 for UDP/TCP DNS)
RUN setcap 'cap_net_bind_service=+ep' /usr/local/bin/python3.12

# Create non-root system user for security
RUN useradd -u 10001 -m -s /bin/bash focusdns && \
    chown -R focusdns:focusdns /app

USER focusdns

# Standard DNS port (UDP & TCP) and DoH / Admin HTTP port
EXPOSE 53/udp 53/tcp 8080/tcp

# Healthcheck to verify DoH and resolver are operational
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["python", "-m", "server.dns_server"]
