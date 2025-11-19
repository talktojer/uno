#!/bin/sh

# Inject environment variables into index.html
sed -i "s|API_BASE_URL_PLACEHOLDER|${API_BASE_URL:-https://uno-api.jersweb.net}|g" /usr/share/nginx/html/index.html
sed -i "s|WS_BASE_URL_PLACEHOLDER|${WS_BASE_URL:-wss://uno-api.jersweb.net}|g" /usr/share/nginx/html/index.html
sed -i "s|BASE_URL_PLACEHOLDER|${BASE_URL:-https://uno.jersweb.net}|g" /usr/share/nginx/html/index.html

# Start nginx
exec nginx -g 'daemon off;'

