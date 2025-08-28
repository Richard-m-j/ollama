# vim: filetype=dockerfile
# STAGE 1: Build environment with necessary compilers and tools
# The --platform flag is redundant and has been removed as per the new warning.
FROM almalinux:8 AS builder
# Install EPEL repo and a COMPLETE C/C++ toolchain (gcc, g++, and binutils).
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf install -y \
      git \
      cmake \
      ccache \
      gcc-toolset-11-gcc \
      gcc-toolset-11-gcc-c++ \
      gcc-toolset-11-binutils && \
    dnf clean all
# Add the newer compiler to the path
ENV PATH=/opt/rh/gcc-toolset-11/root/usr/bin:$PATH
# STAGE 2: Build the CPU backend library
FROM builder AS cpu-builder
WORKDIR /ollama
COPY CMakeLists.txt CMakePresets.json .
COPY ml ml
# Build the CPU library using a cache mount for faster rebuilds
RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CPU' && \
    cmake --build --parallel --preset 'CPU' && \
    cmake --install build --component CPU --strip
# STAGE 3: Build the Go application binary
FROM builder AS go-builder
WORKDIR /go/src/github.com/ollama/ollama
COPY . .
# Install the correct Go version based on go.mod
RUN curl -fsSL "https://golang.org/dl/go$(awk '/^go/ { print $2 }' go.mod).linux-amd64.tar.gz" | tar xz -C /usr/local
ENV PATH=/usr/local/go/bin:$PATH
# Download Go module dependencies and build the binary
ENV CGO_ENABLED=1
RUN --mount=type=cache,target=/root/.cache/go-build \
    go mod download && \
    go build -trimpath -buildmode=pie -o /bin/ollama .
# STAGE 4: Final production image
FROM ubuntu:24.04
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN groupadd -r ollama && useradd --no-log-init -r -g ollama -m ollama
COPY --chown=ollama:ollama --from=go-builder /bin/ollama /usr/bin/ollama
COPY --chown=ollama:ollama --from=cpu-builder /dist/lib/ollama /usr/lib/ollama
USER ollama
ENV OLLAMA_HOST=0.0.0.0:11434
EXPOSE 11434
ENTRYPOINT ["/usr/bin/ollama"]
CMD ["serve"]
