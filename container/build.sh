#!/bin/bash
# Build the NanoClaw agent container image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="nanoclaw-agent"
TAG="${1:-latest}"

echo "Building NanoClaw agent container image..."
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""

# Try building with Apple Container first
echo "Attempting to build with Apple Container..."
if container build --arch arm64 -t "${IMAGE_NAME}:${TAG}" . 2>&1 | tee /tmp/container-build.log; then
    echo ""
    echo "✓ Build complete with Apple Container!"
else
    # If it fails (likely due to Rosetta requirement for buildkit), use Docker instead
    if grep -q "Rosetta" /tmp/container-build.log; then
        echo ""
        echo "Apple Container buildkit requires Rosetta for building."
        echo "Using Docker to build natively for arm64 instead..."
        echo ""

        # Check if Docker is available
        if ! command -v docker &> /dev/null; then
            echo "Error: Docker is not installed. Please install Docker or Rosetta."
            echo "  - Install Docker: https://www.docker.com/products/docker-desktop"
            echo "  - Install Rosetta: softwareupdate --install-rosetta --agree-to-license"
            exit 1
        fi

        # Build with Docker and import to Apple Container
        echo "Building with Docker..."
        docker build --platform linux/arm64 -t "${IMAGE_NAME}:${TAG}" .

        echo ""
        echo "Importing to Apple Container..."
        TMP_TAR="/tmp/${IMAGE_NAME}-${TAG}.tar"
        docker save "${IMAGE_NAME}:${TAG}" -o "$TMP_TAR"
        container image load --input "$TMP_TAR"
        rm "$TMP_TAR"

        echo ""
        echo "✓ Build complete with Docker (imported to Apple Container)!"
    else
        echo ""
        echo "Build failed for unknown reason. Check output above."
        exit 1
    fi
fi

echo ""
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""
echo "Test with:"
echo "  echo '{\"prompt\":\"What is 2+2?\",\"groupFolder\":\"test\",\"chatJid\":\"test@g.us\",\"isMain\":false}' | container run -i ${IMAGE_NAME}:${TAG}"
