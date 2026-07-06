FROM python:3.13-slim

# opencv-python-headless and onnxruntime need these shared libs at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY run.py .

# Model weights (models/) and the FAISS index (face_index/) are mounted as
# volumes at runtime, not baked into the image — contactless_embedding.onnx
# alone is ~1.1GB and changes independently of the app code.
ENV EMBEDDING_MODEL_PATH=/app/models/contactless_embedding.onnx

EXPOSE 5001
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "5001"]
