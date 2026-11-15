# Baut die Server-Binary ohne CGO und packt sie in ein minimales Image (mit CA-Zertifikaten für die Claude API).
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /koerperkompass .

FROM gcr.io/distroless/static-debian12
COPY --from=build /koerperkompass /koerperkompass
ENV KK_DB=/data/koerperkompass.db PORT=8080
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/koerperkompass"]
