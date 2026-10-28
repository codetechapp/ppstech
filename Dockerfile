FROM alpine:3.20

RUN apk add --no-cache bash caddy wget unzip ca-certificates \
 && wget -q -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip \
 && unzip -q /tmp/xray.zip xray -d /usr/local/bin \
 && rm /tmp/xray.zip \
 && chmod +x /usr/local/bin/xray

COPY start.sh /start.sh
RUN chmod +x /start.sh

ENV PORT=8080
EXPOSE 8080
CMD ["/start.sh"]
