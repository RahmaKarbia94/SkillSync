FROM golang:1.24-alpine AS base

RUN apk add --no-cache git curl bash

WORKDIR /app

RUN go install github.com/air-verse/air@v1.61.1

COPY go.mod go.sum ./
RUN go mod download

COPY . .

EXPOSE 8080

ENTRYPOINT ["air", "-c", ".air.toml"]