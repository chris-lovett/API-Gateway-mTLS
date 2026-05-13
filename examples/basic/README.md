# Basic Setup Example

This directory contains a minimal working configuration for F5 LTM to Consul API Gateway with mTLS.

## Prerequisites

- F5 LTM with admin access
- OpenShift/Kubernetes cluster with Consul deployed
- Venafi TPP or Cloud instance
- `kubectl` CLI tool
- `vcert` CLI tool

## Quick Start

### 1. Set Environment Variables

```bash
export VENAFI_URL="https://venafi.example.com/vedsdk"
export VENAFI_TOKEN="your-venafi-token"
export F5_HOST="f5-lb-01.example.com"
export F5_USER="admin"
export F5_PASS="your-f5-password"
```

### 2. Generate Certificates

```bash
# Generate API Gateway server certificate
cd ../../venafi/scripts
./request-gateway-cert.sh

# Generate F5 client certificate
./request-f5-client-cert.sh
```

### 3. Deploy to Kubernetes

```bash
# Deploy everything
cd ../../scripts
./deploy.sh
```

### 4. Configure F5

```bash
# Upload certificates to F5
cd ../../venafi/scripts/certs
F5_HOST=$F5_HOST F5_USER=$F5_USER F5_PASS=$F5_PASS ./upload-to-f5.sh

# Apply F5 configuration
ssh admin@$F5_HOST "tmsh -f /path/to/server-ssl-profile.tmsh"
ssh admin@$F5_HOST "tmsh -f /path/to/client-ssl-profile.tmsh"
ssh admin@$F5_HOST "tmsh -f /path/to/api-gateway-pool.tmsh"
ssh admin@$F5_HOST "tmsh -f /path/to/api-gateway-vs.tmsh"
```

### 5. Verify

```bash
cd ../../scripts
./verify.sh
```

## Configuration Files

This basic setup includes:

- **Venafi Certificates**: API Gateway server cert and F5 client cert
- **F5 Configuration**: SSL profiles, pool, and virtual server
- **Consul Gateway**: Gateway, GatewayClass, and basic HTTPRoute
- **Backend Service**: Single backend service with Consul Connect
- **Network Policies**: Basic ingress restrictions

## Testing

### Test from F5

```bash
# From F5 CLI
curl -v https://api-gateway.consul.svc.cluster.local/health \
  --cert /config/ssl/ssl.crt/f5-client-cert.crt \
  --key /config/ssl/ssl.key/f5-client-key.key \
  --cacert /config/ssl/ssl.crt/venafi-ca-bundle.crt
```

### Test from External Client

```bash
# Through F5 virtual server
curl -v https://api.example.com/api/v1/health
```

## Troubleshooting

### Issue: Certificate validation failed

**Solution**: Verify certificate chain
```bash
openssl verify -CAfile venafi-ca-bundle.crt gateway-server.crt
openssl verify -CAfile venafi-ca-bundle.crt f5-client.crt
```

### Issue: Connection refused

**Solution**: Check NetworkPolicy
```bash
kubectl get networkpolicy -n consul
kubectl describe networkpolicy api-gateway-ingress-f5-only -n consul
```

### Issue: Gateway not ready

**Solution**: Check Gateway status
```bash
kubectl describe gateway api-gateway -n consul
kubectl logs -n consul -l app=api-gateway
```

## Next Steps

1. Review the [production setup](../production/) for a more robust configuration
2. Add monitoring and alerting
3. Configure certificate rotation
4. Set up additional backend services
5. Implement rate limiting and WAF rules

## Support

For issues or questions, refer to:
- [Architecture Documentation](../../docs/architecture.md)
- [Best Practices](../../docs/best-practices.md)
- [Troubleshooting Guide](../../docs/troubleshooting.md)