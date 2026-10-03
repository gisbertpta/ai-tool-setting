FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends squid \
    && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf
# allowlist.txt, the modules' (generated) and the project's allowlists are bind-mounted by docker-compose.yml

EXPOSE 3128
# Run squid in the foreground and stream the access log; the container exits if squid dies
CMD ["sh", "-c", "touch /var/log/squid/access.log && chown proxy:proxy /var/log/squid/access.log; squid -N -d 1 -f /etc/squid/squid.conf & exec tail -F --pid=$! /var/log/squid/access.log"]
