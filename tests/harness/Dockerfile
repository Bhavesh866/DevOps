# Builder stage: pip exists only here, never in the runtime image.
FROM python:3.13-alpine AS deps
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --target /deps -r /tmp/requirements.txt

FROM python:3.13-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/deps \
    ROLE=api \
    APP_VERSION=synthetic-v1

# Pull fixed Alpine packages that are newer than the base image snapshot.
RUN apk upgrade --no-cache && addgroup -S app && adduser -S -G app app
WORKDIR /app

RUN rm -rf \
    /usr/local/lib/python3.13/site-packages/pip \
    /usr/local/lib/python3.13/site-packages/pip-*.dist-info \
    /usr/local/bin/pip \
    /usr/local/bin/pip3 \
    /usr/local/bin/pip3.13

COPY --from=deps /deps /app/deps
COPY app.py /app/app.py

USER app:app
EXPOSE 8080

CMD ["python", "/app/app.py"]
