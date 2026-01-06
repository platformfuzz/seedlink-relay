# Multi-stage build for seedlink-relay (ringserver + slink2dali)
# Stage 1: Build both ringserver and slink2dali
FROM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    make \
    gcc \
    musl-dev

# Build ringserver
WORKDIR /build/ringserver
RUN git clone --depth 1 https://github.com/EarthScope/ringserver.git . && \
    make

# Install ringserver binary
RUN mkdir -p /usr/local/bin && \
    if [ -f ./ringserver ]; then \
        install -m 755 ./ringserver /usr/local/bin/ringserver; \
    else \
        find . -name "ringserver" -type f -executable -exec install -m 755 {} /usr/local/bin/ringserver \; && \
        test -f /usr/local/bin/ringserver || (echo "ERROR: ringserver binary not found after build" && find . -type f && exit 1); \
    fi

# Build slink2dali (has dependencies: libslink, libdali, libmseed - all in the repo)
WORKDIR /build/slink2dali
RUN git clone --depth 1 https://github.com/EarthScope/slink2dali.git . && \
    export CFLAGS="-std=gnu89 -fno-strict-aliasing -Wno-error -Wno-incompatible-pointer-types" && \
    make && \
    test -f slink2dali

# Install slink2dali binary (built in root directory)
RUN if [ -f ./slink2dali ]; then \
        install -m 755 ./slink2dali /usr/local/bin/slink2dali; \
    else \
        find . -name "slink2dali" -type f -executable -exec install -m 755 {} /usr/local/bin/slink2dali \; && \
        test -f /usr/local/bin/slink2dali || (echo "ERROR: slink2dali binary not found after build" && find . -type f && exit 1); \
    fi

# Build slinktool (has dependencies: libslink, ezxml)
WORKDIR /build/slinktool
RUN git clone --depth 1 https://github.com/EarthScope/slinktool.git . && \
    export CFLAGS_LIBSLINK="-std=gnu89 -fno-strict-aliasing -Wno-error -Wno-incompatible-pointer-types" && \
    export CFLAGS_EZXML="-std=gnu99 -fno-strict-aliasing -Wno-error" && \
    cd libslink && \
    make CFLAGS="$CFLAGS_LIBSLINK" && \
    cd ../ezxml && \
    make CFLAGS="$CFLAGS_EZXML" && \
    cd ../src && \
    make && \
    cd .. && \
    test -f slinktool

# Install slinktool binary
RUN if [ -f ./slinktool ]; then \
        install -m 755 ./slinktool /usr/local/bin/slinktool; \
    else \
        find . -name "slinktool" -type f -executable -exec install -m 755 {} /usr/local/bin/slinktool \; && \
        test -f /usr/local/bin/slinktool || (echo "ERROR: slinktool binary not found after build" && find . -type f && exit 1); \
    fi

# Verify all binaries exist
RUN test -f /usr/local/bin/ringserver && \
    test -f /usr/local/bin/slink2dali && \
    test -f /usr/local/bin/slinktool && \
    /usr/local/bin/slink2dali -h && \
    /usr/local/bin/slinktool -h

# Stage 2: Runtime image
FROM alpine:latest

# Install runtime dependencies (minimal - just what's needed to run)
RUN apk add --no-cache \
    ca-certificates \
    netcat-openbsd

# Copy all binaries from builder
COPY --from=builder /usr/local/bin/ringserver /usr/local/bin/ringserver
COPY --from=builder /usr/local/bin/slink2dali /usr/local/bin/slink2dali
COPY --from=builder /usr/local/bin/slinktool /usr/local/bin/slinktool

# Verify and set permissions
RUN chmod +x /usr/local/bin/ringserver && \
    chmod +x /usr/local/bin/slink2dali && \
    chmod +x /usr/local/bin/slinktool

# Create non-root user
RUN addgroup -g 1000 ringserver && \
    adduser -D -u 1000 -G ringserver ringserver

# Create directories for data and config
RUN mkdir -p /data /config /datalink-state && \
    chown -R ringserver:ringserver /data /config /datalink-state

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set working directory
WORKDIR /data

# Expose ports
EXPOSE 18000 16000

# Switch to non-root user
USER ringserver

# Default entrypoint (can be overridden in docker-compose)
ENTRYPOINT ["/entrypoint.sh"]
