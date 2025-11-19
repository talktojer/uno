# Multi-stage build for Flutter web app
FROM dart:stable AS build

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git /flutter
ENV PATH="/flutter/bin:$PATH"
ENV FLUTTER_ROOT=/flutter

# Enable web support and pre-download artifacts
RUN flutter config --enable-web
RUN flutter doctor

# Set working directory
WORKDIR /app

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock* ./

# Get dependencies
RUN flutter pub get

# Copy source code
COPY . .

# Build web app (web platform should now be configured)
RUN flutter build web --release

# Stage 2: Runtime image
FROM nginx:alpine AS runtime

# Copy built web app to nginx
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose port
EXPOSE 80

# Use entrypoint script to inject environment variables
ENTRYPOINT ["/entrypoint.sh"]
