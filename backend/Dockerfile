FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/server ./cmd/server
RUN CGO_ENABLED=0 go build -o /out/worker ./cmd/worker
RUN CGO_ENABLED=0 go build -o /out/migrate ./cmd/migrate

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /out/server /usr/local/bin/eggfarm-server
COPY --from=build /out/worker /usr/local/bin/eggfarm-worker
COPY --from=build /out/migrate /usr/local/bin/eggfarm-migrate
COPY migrations ./migrations
EXPOSE 8080
# CMD rather than ENTRYPOINT so one image serves every process: Render's dockerCommand (see
# render.yaml) swaps in eggfarm-worker or eggfarm-migrate, which an ENTRYPOINT would block.
CMD ["eggfarm-server"]
