# FocusDNS Production Multi-Stage Dockerfile
# Stage 1: Build binary
FROM golang:1.22-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git ca-certificates tzdata

COPY go.mod ./
# If go.sum exists, copy it
# RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/focusdns-api ./cmd/server/main.go

# Stage 2: Lightweight runtime image
FROM alpine:3.19

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/focusdns-api /app/focusdns-api
COPY internal/storage/schema.sql /app/schema.sql

EXPOSE 8080

USER 1000:1000

ENTRYPOINT ["/app/focusdns-api"]
