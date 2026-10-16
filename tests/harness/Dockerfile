FROM python:3.13-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ROLE=api \
    APP_VERSION=synthetic-v1

# Pull fixed Alpine packages that are newer than the base image snapshot.
RUN apk upgrade --no-cache && addgroup -S app && adduser -S -G app app
WORKDIR /app

COPY app.py /app/app.py
RUN rm -rf \
    /usr/local/lib/python3.13/site-packages/pip \
    /usr/local/lib/python3.13/site-packages/pip-*.dist-info \
    /usr/local/bin/pip \
    /usr/local/bin/pip3 \
    /usr/local/bin/pip3.13

USER app:app
EXPOSE 8080

CMD ["python", "/app/app.py"]
