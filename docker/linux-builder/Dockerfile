FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV QT_DIR=/opt/Qt
ENV QT_VERSION=6.6.3

# ── System dependencies ────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build pkg-config \
    gcc g++ \
    libavcodec-dev libavformat-dev libavutil-dev \
    libswscale-dev libswresample-dev \
    libassimp-dev libarchive-dev libmagic-dev \
    libgl1-mesa-dev libvulkan-dev \
    ffmpeg poppler-utils pandoc \
    python3 python3-pip \
    wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ── Qt 6.6.3 via aqt ──────────────────────────────────────────────────────────
RUN pip3 install --no-cache-dir aqtinstall && \
    aqt install-qt linux desktop ${QT_VERSION} gcc_64 \
        --outputdir ${QT_DIR} \
        --modules qtquick3d && \
    pip3 uninstall -y aqtinstall && \
    rm -rf ~/.cache/pip

# ── Environment for cmake find_package(Qt6) ───────────────────────────────────
ENV CMAKE_PREFIX_PATH=${QT_DIR}/${QT_VERSION}/gcc_64
ENV PATH=${QT_DIR}/${QT_VERSION}/gcc_64/bin:${PATH}
ENV LD_LIBRARY_PATH=${QT_DIR}/${QT_VERSION}/gcc_64/lib
