FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      mysql-client postgresql-client inotify-tools \
      curl wget gnupg pigz ca-certificates && \
    wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - && \
    echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse' \
      > /etc/apt/sources.list.d/mongodb-org-7.0.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends mongodb-org-tools && \
    rm -rf /var/lib/apt/lists/*

COPY import.sh /import.sh
RUN chmod +x /import.sh

ENTRYPOINT ["bash", "/import.sh"]
