# =====================================================================
# Orbit 积分后端镜像
# 两阶段构建：第一阶段带编译工具装依赖（better-sqlite3 下载不到预编译
# 包时会现场编译），第二阶段只保留运行必需的文件，镜像更小更安全。
# =====================================================================

# ---- 阶段 1：安装依赖 ----
FROM node:24-slim AS builder
# 软件源换成阿里云，避免国内从 Debian 官方源（deb.debian.org）慢速下载
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do \
      [ -f "$f" ] && sed -i 's|deb.debian.org|mirrors.aliyun.com|g' "$f"; \
    done; \
    apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*
# npm 依赖和 better-sqlite3 预编译包都走国内镜像，避免访问 npmjs / GitHub 缓慢
ENV npm_config_better_sqlite3_binary_host_mirror=https://registry.npmmirror.com/-/binary/better-sqlite3
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --registry=https://registry.npmmirror.com

# ---- 阶段 2：运行镜像 ----
FROM node:24-slim
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY public ./public
COPY certs ./certs

ENV NODE_ENV=production
# 容器内固定 8080，对外端口在 docker-compose.yml 里映射
ENV PORT=8080
EXPOSE 8080

CMD ["node", "src/server.js"]
