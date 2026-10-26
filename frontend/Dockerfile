# ------------------------------------------------------------
# Frontend build image: produces the static React files for S3.
# Nothing runs in a container in production; CloudFront serves
# the files from S3. This image only builds them reproducibly.
#
# Usage (writes the built site to ./dist on your machine):
#   docker build \
#     --build-arg VITE_API_URL=https://api.example.com \
#     --output type=local,dest=./dist \
#     ./frontend
# Then upload it:
#   aws s3 sync ./dist s3://<bucket> --delete
# ------------------------------------------------------------

# ---- Stage 1: build the site with Node ----
FROM node:24 AS build
WORKDIR /app

# Install dependencies first so this layer is cached when only code changes.
# npm ci = clean, exact install from package-lock.json
COPY package*.json ./
RUN npm ci

COPY . .

# Vite bakes VITE_* variables into the JS at build time. frontend/.env is
# excluded by .dockerignore, so the backend URL must be passed as a build arg.
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL

# tsc type-check + vite production build -> /app/dist
RUN npm run build

# ---- Stage 2: export only the built files ----
# "scratch" is an empty image; with --output the files land on your machine
FROM scratch AS export
COPY --from=build /app/dist /
