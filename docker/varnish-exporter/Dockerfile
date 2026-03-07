# ---------------------------------------
# 1) Build stage: compile prometheus_varnish_exporter
# ---------------------------------------
FROM golang:1.18 AS builder
WORKDIR /go/src/varnish_exporter

# Use the jonnenauha exporter v1.6.1 (Cloud Monitoring requires ≥1.6.1)
RUN go mod init varnish_exporter
RUN go install github.com/jonnenauha/prometheus_varnish_exporter@1.6.1

# ---------------------------------------
# 2) Final image: Varnish 7.7 + exporter binary
# ---------------------------------------
FROM varnish:7.7
# Copy the compiled exporter into /usr/local/bin
COPY --from=builder /go/bin/prometheus_varnish_exporter /usr/local/bin/

# Expose exporter port (9131) so Kubernetes Service can route to it
EXPOSE 9131

# Default entrypoint just runs the exporter; we'll override in Deployment to run as a sidecar
ENTRYPOINT ["/usr/local/bin/prometheus_varnish_exporter"]
