# Huntarr Patched - Security-hardened build
FROM python:3.11-slim

# Environment
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV TZ=UTC

# Default UID/GID (Unraid defaults)
ARG PUID=99
ARG PGID=100
ENV PUID=${PUID}
ENV PGID=${PGID}

# Default UMASK (Unraid standard)
ARG UMASK=022
ENV UMASK=${UMASK}

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Create group and user dynamically based on PUID/PGID
RUN groupadd -g ${PGID} huntarr \
    && useradd -u ${PUID} -g ${PGID} -m -s /bin/bash huntarr

# Create app directory
WORKDIR /app

# Copy requirements first for caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code with correct ownership
COPY --chown=${PUID}:${PGID} . .

# Create config directory with proper permissions
RUN mkdir -p /config && chown -R ${PUID}:${PGID} /config

# Set config environment variable
ENV HUNTARR_CONFIG_DIR=/config

# Expose port
EXPOSE 9705

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:9705/api/health', timeout=5)" || exit 1

# Switch to non-root user
USER huntarr

# Apply UMASK at runtime and start the app
CMD ["bash", "-c", "umask ${UMASK} && python main.py"]
