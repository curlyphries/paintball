# All-in-one: relay server + static game files served by nginx
# Usage: docker run -p 8080:80 -p 9090:9090 ghcr.io/curlyphries/paintball
FROM node:20-alpine AS relay
WORKDIR /app
COPY server/package.json ./
RUN npm install --production
COPY server/index.js ./

FROM nginx:alpine
# Copy relay server
COPY --from=relay /usr/local/bin/node /usr/local/bin/node
COPY --from=relay /app /opt/relay
# Copy game files
COPY export/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE 80 9090
CMD ["/start.sh"]
