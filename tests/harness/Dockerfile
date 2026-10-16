FROM python:3.13-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ROLE=api \
    APP_VERSION=synthetic-v1

RUN addgroup -S app && adduser -S -G app app
WORKDIR /app

COPY app.py /app/app.py

USER app:app
EXPOSE 8080

CMD ["python", "/app/app.py"]
