# Huntarr Patched - Security-hardened build
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV TZ=UTC

# Default to non-root user (override with -e PUID/PGID at runtime)
ENV PUID=1000
ENV PGID=1000

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user and group - Match unraid defaults
RUN groupadd -g 100 huntarr && \
    useradd -u 99 -g huntarr -m -s /bin/bash huntarr

# Create app directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY --chown=huntarr:huntarr . .

# Create config directory with proper permissions
RUN mkdir -p /config && chown -R huntarr:huntarr /config

# Set config environment variable
ENV HUNTARR_CONFIG_DIR=/config

# Expose port
EXPOSE 9705

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:9705/api/health', timeout=5)" || exit 1

# Switch to non-root user
USER huntarr

# Run the application
CMD ["python", "main.py"]
