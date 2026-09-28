# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
# Stage 1 `builder`: cài dependency vào /install (có thể cần compiler).
# Stage 2 `runtime`: chỉ copy kết quả cài đặt + source code, chạy non-root.
#
# Bản 1 stage ban đầu được giữ ở Dockerfile.single để so sánh dung lượng.
# ═══════════════════════════════════════════════════════════════════

FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Copy riêng requirements trước để layer pip install được cache
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt


FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# User thường, không có quyền root
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

COPY --from=builder /install /usr/local

# Source code copy SAU cùng — sửa code không làm mất cache dependency
COPY --chown=appuser:appuser utils ./utils
COPY --chown=appuser:appuser app ./app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\", \"8000\")}/health', timeout=4).read()" || exit 1

# Dạng shell để ${PORT} được nội suy — cloud tự gán cổng
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
