# syntax=docker/dockerfile:1

FROM node:22-bookworm AS frontend-build
WORKDIR /build/chess-frontend

COPY chess-frontend/package.json chess-frontend/package-lock.json ./
RUN npm ci

COPY chess-frontend/ ./
RUN npm run build

FROM maven:3.9-eclipse-temurin-21 AS api-build
WORKDIR /build

COPY pom.xml ./pom.xml
COPY spring-annotation-context-initializer-template/ ./spring-annotation-context-initializer-template/
COPY chess/ ./chess/
COPY chess-database/ ./chess-database/
COPY chess-api/ ./chess-api/

RUN mvn -f /build/pom.xml clean package -DskipTests -Dexec.skip=true

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/games:${PATH}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common ca-certificates && \
    add-apt-repository universe && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        apache2 \
        openjdk-21-jre-headless \
        openssl \
        stockfish \
        fairy-stockfish \
        fruit \
        toga2 && \
    a2enmod proxy proxy_http proxy_wstunnel rewrite ssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/ssl/certs /etc/ssl/private && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/apache-selfsigned.key \
        -out /etc/ssl/certs/apache-selfsigned.crt \
        -subj "/CN=127.0.0.1" \
        -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"

WORKDIR /app

COPY --from=api-build /build/chess-api/target/chess-app.jar /app/chess-api.jar
COPY --from=frontend-build /build/chess-frontend/dist/ /var/www/html/

COPY docker/apache-config.conf /etc/apache2/sites-available/000-default.conf
COPY docker/apache-ssl.conf /etc/apache2/sites-available/default-ssl.conf
RUN a2ensite default-ssl.conf

EXPOSE 80 443

CMD ["bash", "-lc", "service apache2 start && exec java -Xmx4g -Xms512m -jar /app/chess-api.jar"]
