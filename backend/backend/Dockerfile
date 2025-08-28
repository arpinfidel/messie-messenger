FROM golang:1.24.6-alpine
WORKDIR /app

# Use the module proxy and force IPv4 so Go won’t try IPv6
ENV GOPROXY=https://proxy.golang.org,direct
ENV GODEBUG=ipv6=0

# Better caching
COPY go.mod go.sum ./
RUN go mod download

# Build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o service ./main.go

EXPOSE 8080
ENTRYPOINT ["./service"]
