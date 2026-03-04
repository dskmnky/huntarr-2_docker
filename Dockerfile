FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV TZ=UTC

# Default Unraid values
ENV PUID=99
ENV PGID=100
ENV UMASK=022

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Install gosu for privilege dropping
RUN apt-get update && apt-get install -y --no-install-recommends gosu \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements first
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create config directory
RUN mkdir -p /config

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV HUNTARR_CONFIG_DIR=/config

EXPOSE 9705

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 - << 'EOF' || exit 1
import requests
requests.get("http://localhost:9705/api/health", timeout=5)
EOF

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "main.py"]
