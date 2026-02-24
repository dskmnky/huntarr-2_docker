"""
Secure CORS helper - only allows same-origin or configured origins.
"""
from flask import request
import os

# Configurable allowed origins (comma-separated) via env var
# Default: only same-origin (empty = same-origin only)
_ALLOWED_ORIGINS = [o.strip() for o in os.environ.get('HUNTARR_CORS_ORIGINS', '').split(',') if o.strip()]

def get_cors_origin():
    """
    Returns the origin to use for Access-Control-Allow-Origin.
    Returns None if origin should not be allowed (same-origin will work by default).
    """
    origin = request.headers.get('Origin')
    if not origin:
        return None  # Same-origin request, no CORS needed
    
    # Check if origin is in allowed list
    if origin in _ALLOWED_ORIGINS:
        return origin
    
    # Check if it's the same host (different port is OK for dev)
    request_host = request.host.split(':')[0]
    origin_host = origin.replace('http://', '').replace('https://', '').split(':')[0]
    
    if request_host == origin_host:
        return origin  # Same host, allow it
    
    # For local development
    if origin_host in ('localhost', '127.0.0.1') and request_host in ('localhost', '127.0.0.1'):
        return origin
    
    return None  # Don't allow cross-origin

def add_cors_headers(response):
    """Add CORS headers to response if origin is allowed."""
    origin = get_cors_origin()
    if origin:
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    return response
