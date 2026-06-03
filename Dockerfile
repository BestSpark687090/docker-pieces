# -------- Stage 1: clone the repo --------
FROM alpine:latest AS fetch

RUN apk add --no-cache git

WORKDIR /site
ARG CACHEBUST
RUN git clone https://github.com/BestSpark687090/BestSpark687090.git
RUN git clone https://github.com/BestSpark687090/ultraviolet-proxy.git
RUN git clone https://github.com/BestSpark687090/scramjet-proxy.git
RUN git clone https://github.com/BestSpark687090/website-server-modifications.git


# Apply server modifications 
#RUN cp /site/website-server-modifications/register-sw.js /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/register-sw.js
#RUN cp /site/website-server-modifications/uv.config.js /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/uv/uv.config.js
RUN cp /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/search.js /site/scramjet-proxy/public/search.js
#RUN cp /site/website-server-modifications/sw.js /site/scramjet-proxy/public/sw.js

# webserver mods: instead of using register-sw diff just sed the stockSW var or whatever
RUN sed 's|/uv/sw.js|/pxy/uv/sw.js|g' /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/register-sw.js > /tmp/register-sw.js && \
    mv /tmp/register-sw.js /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/register-sw.js

# webserver mods: replace /uv/ with /pxy/uv/ in the UV config
RUN sed 's|/uv/|/pxy/uv/|g' /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/uv/uv.config.js > /tmp/uv.config.js && \
    mv /tmp/uv.config.js /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/uv/uv.config.js

# Fix paths to include /pxy prefix
RUN sed 's|/baremux/worker.js|/pxy/baremux/worker.js|g; s|/epoxy/index.mjs|/pxy/epoxy/index.mjs|g' \
        /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/index.js > /tmp/uv-index.js && \
    mv /tmp/uv-index.js /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/index.js

# Ultraviolet: Change /uv/ to /ultrav/ because it's detecting it
RUN find /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/ -type f -exec sed -i 's|/uv/|/ultrav/|g; s|src="uv/|src="ultrav/|g; s|uv\.config\.js|uv.conf.js|g' {} + && \
    mv /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/uv/uv.config.js \
       /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/uv/uv.conf.js
RUN sed -i 's|uv/uv.|ultrav/uv.|g' /site/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static/public/index.html
# Fix paths on Scramjet
RUN sed -i 's|/~/sj/|/sjp/~/sj/|g; s|/scramjet/scramjet.js|/sjp/scramjet/scramjet.js|g; s|/controller/controller.inject.js|/sjp/controller/controller.inject.js|g; s|/scramjet/scramjet.wasm|/sjp/scramjet/scramjet.wasm|g; s|/libcurl/index.mjs|/sjp/libcurl/index.mjs|g; s|/dark-inject.js|/sjp/dark-inject.js|g' \
        /site/scramjet-proxy/public/index.js
RUN sed -i 's|/controller/controller.sw.js|/sjp/controller/controller.sw.js|g; s|/config.js|/sjp/config.js|g' \
        /site/scramjet-proxy/public/sw.js
RUN sed -i 's|/scramjet/scramjet.js|/sjp/scramjet/scramjet.js|g; s|/controller/controller.api.js|/sjp/controller/controller.api.js|g; s|/scramjet-utils/scramjet-utils.js|/sjp/scramjet-utils/scramjet-utils.js|g' \
        /site/scramjet-proxy/public/index.html

# Grab main server through modifications
RUN cp /site/website-server-modifications/server.js /site/server.js
RUN cp /site/website-server-modifications/package.json /site/package.json
# -------- Stage 2: run Node.js server --------
FROM node:20-alpine

WORKDIR /app

# Copy everything from /site
COPY --from=fetch /site /app

# Install curl for TLS-fingerprint-accurate proxying
RUN apk add --no-cache curl

# Install dependencies from root package.json
RUN npm install
RUN npm install /app/ultraviolet-proxy/Ultraviolet-App/Ultraviolet-Static

EXPOSE 8080

# Run server.js from root
CMD ["node", "/app/server.js"]
