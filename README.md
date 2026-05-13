# F5 LTM to Consul API Gateway mTLS Configuration

This repository contains configuration files and best practices for implementing end-to-end mutual TLS (mTLS) between F5 Load Balancers and Consul API Gateway on OpenShift, using Venafi-issued certificates.

## Architecture Overview

```
[External Client]
      ↓ HTTPS (Public CA)
[F5 LTM Load Balancer]
      ↓ mTLS (Venafi-issued certs)
[Consul API Gateway]
      ↓ mTLS (Consul Connect)
[Backend Services]
```

This pattern gives platform operators a clear separation of responsibilities across the ingress path:

- **External TLS is terminated at F5** using the certificate and policy appropriate for north-south traffic.
- **F5 re-encrypts upstream traffic with mTLS** so the connection to Consul API Gateway is authenticated on both sides.
- **Consul API Gateway enforces trusted ingress into the cluster** and hands traffic into the service mesh.
- **Backend services continue to use Consul Connect mTLS** for east-west communication.

In practice, this means the edge, ingress, and service-mesh trust domains remain distinct while still participating in a secure end-to-end request path.

## Key Principles

1. **Terminate and Re-encrypt**: F5 terminates external TLS and re-encrypts with mTLS to API Gateway
2. **Separate PKI Hierarchies**: Venafi for edge ingress, Consul CA for service mesh
3. **Mutual Authentication**: Both F5 and API Gateway validate each other's certificates
4. **Automated Rotation**: Certificates managed through Venafi with automated renewal

## Repository Structure

```
.
├── README.md                          # This file
├── docs/                              # Documentation
│   ├── architecture.md                # Detailed architecture guide
│   ├── best-practices.md              # Security best practices
│   ├── troubleshooting.md             # Troubleshooting guide
│   └── certificate-rotation.md        # Certificate lifecycle management
├── venafi/                            # Venafi certificate configurations
│   ├── policies/                      # Venafi policy definitions
│   ├── scripts/                       # Certificate request/renewal scripts
│   └── examples/                      # Example certificate requests
├── f5/                                # F5 LTM configurations
│   ├── ssl-profiles/                  # SSL profile configurations
│   ├── virtual-servers/               # Virtual server definitions
│   ├── pools/                         # Pool configurations
│   └── scripts/                       # F5 automation scripts
├── consul-gateway/                    # Consul API Gateway manifests
│   ├── gateway.yaml                   # Gateway configuration
│   ├── gateway-class.yaml             # GatewayClass configuration
│   ├── routes/                        # HTTPRoute definitions
│   └── intentions/                    # Service intentions
├── kubernetes/                        # Kubernetes/OpenShift resources
│   ├── secrets/                       # Secret templates
│   ├── configmaps/                    # ConfigMap templates
│   ├── network-policies/              # NetworkPolicy definitions
│   ├── services/                      # Service definitions
│   └── deployments/                   # Deployment manifests
├── monitoring/                        # Monitoring and alerting
│   ├── prometheus/                    # Prometheus rules
│   ├── grafana/                       # Grafana dashboards
│   └── alerts/                        # Alert definitions
├── scripts/                           # Automation scripts
│   ├── deploy.sh                      # Deployment script
│   ├── verify.sh                      # Verification script
│   ├── rotate-certs.sh                # Certificate rotation
│   └── troubleshoot.sh                # Troubleshooting helper
└── examples/                          # Complete examples
    ├── basic/                         # Basic setup
    ├── production/                    # Production-ready setup
    └── testing/                       # Testing configurations
```

## Quick Start

This quickstart walks through how to stand up a secure ingress path from F5 LTM to Consul API Gateway using mutual TLS. It is written for platform operators who want to understand both **what they are doing** and **which commands to run**.

By the end of this process, you will have:

- requested and generated the certificates needed for mutual authentication,
- configured F5 to terminate external TLS and re-establish trust upstream,
- deployed Consul API Gateway with the required certificates and trust bundles, and
- verified that traffic is flowing securely from the edge into the mesh.

### Prerequisites

Before you begin, make sure you have access to all systems involved in the trust chain:

- F5 LTM with admin access
- OpenShift cluster with Consul deployed
- Venafi TPP or Cloud instance
- `kubectl` and `oc` CLI tools
- `vcert` CLI tool
- `tmsh` access to F5

It is also helpful to clone the repository locally so you can run the scripts directly:

```bash
git clone https://github.com/chris-lovett/API-Gateway-mTLS.git
cd API-Gateway-mTLS
```

### 1. Issue certificates from Venafi

The first step is to establish identity on both sides of the F5-to-gateway connection.

At this stage, you are creating:
- a **server certificate** for the Consul API Gateway, so F5 can verify the gateway it connects to, and
- a **client certificate** for F5, so the gateway can require F5 to authenticate with a trusted certificate.

This is the foundation for mutual TLS between the load balancer and the gateway.

Run:

```bash
cd venafi/scripts
./request-gateway-cert.sh
./request-f5-client-cert.sh
cd ../..
```

When this step is complete, you should have the certificate artifacts needed to configure both the gateway and F5.

### 2. Configure F5 LTM as the secure edge and upstream mTLS client

Next, configure F5 so it can accept external HTTPS traffic and then re-encrypt upstream traffic to Consul API Gateway using mTLS.

Operationally, this step:
- uploads the relevant certificates and keys to F5,
- configures the SSL profiles that define how inbound and outbound TLS are handled, and
- creates the virtual server and pool that forward traffic to the gateway.

In other words, F5 becomes the edge entry point for clients and the authenticated client of the API Gateway.

Run:

```bash
cd f5/scripts
./upload-certs.sh
./configure-f5.sh
cd ../..
```

After this step, F5 should be prepared to initiate a mutually authenticated TLS session to the gateway.

### 3. Deploy Consul API Gateway with the required trust material

With F5 ready, the next step is to configure the cluster-side ingress components.

From an operator’s perspective, this step:
- creates Kubernetes secrets and related configuration for the gateway certificate and CA material,
- deploys the Consul API Gateway resources, and
- enables the gateway to validate incoming client certificates rather than accepting anonymous upstream connections.

This is where the cluster becomes ready to trust only approved upstream clients such as F5.

Run:

```bash
cd scripts
./deploy.sh
cd ..
```

After deployment, the gateway should be present in the cluster and configured to participate in the intended trust model.

### 4. Verify the end-to-end configuration

The final step is to confirm that the secure ingress path is actually working as designed.

This verification step should validate that:
- the certificates were issued and installed correctly,
- F5 can successfully establish mTLS to the API Gateway,
- the gateway requires and validates client certificates, and
- requests can continue onward to backend services through Consul.

Run:

```bash
cd scripts
./verify.sh
cd ..
```

At the end of this step, you should have confidence that the deployment is not only present, but correctly enforcing trust across the ingress path.

## Configuration Files

### Venafi Certificates

- [`venafi/policies/gateway-server-policy.json`](venafi/policies/gateway-server-policy.json) - API Gateway server certificate policy
- [`venafi/policies/f5-client-policy.json`](venafi/policies/f5-client-policy.json) - F5 client certificate policy
- [`venafi/scripts/request-gateway-cert.sh`](venafi/scripts/request-gateway-cert.sh) - Request gateway certificate
- [`venafi/scripts/request-f5-client-cert.sh`](venafi/scripts/request-f5-client-cert.sh) - Request F5 client certificate

### F5 Configuration

- [`f5/ssl-profiles/client-ssl-profile.tmsh`](f5/ssl-profiles/client-ssl-profile.tmsh) - Client-side SSL profile
- [`f5/ssl-profiles/server-ssl-profile.tmsh`](f5/ssl-profiles/server-ssl-profile.tmsh) - Server-side SSL profile (mTLS)
- [`f5/virtual-servers/api-gateway-vs.tmsh`](f5/virtual-servers/api-gateway-vs.tmsh) - Virtual server configuration
- [`f5/pools/api-gateway-pool.tmsh`](f5/pools/api-gateway-pool.tmsh) - Backend pool configuration

### Consul API Gateway

- [`consul-gateway/gateway.yaml`](consul-gateway/gateway.yaml) - Gateway with mTLS client validation
- [`consul-gateway/gateway-class.yaml`](consul-gateway/gateway-class.yaml) - GatewayClass configuration
- [`consul-gateway/routes/backend-route.yaml`](consul-gateway/routes/backend-route.yaml) - Example HTTPRoute
- [`consul-gateway/intentions/gateway-to-backend.yaml`](consul-gateway/intentions/gateway-to-backend.yaml) - Service intentions

### Kubernetes Resources

- [`kubernetes/secrets/gateway-tls-secret.yaml`](kubernetes/secrets/gateway-tls-secret.yaml) - Gateway TLS secret template
- [`kubernetes/configmaps/venafi-ca-bundle.yaml`](kubernetes/configmaps/venafi-ca-bundle.yaml) - Venafi CA bundle
- [`kubernetes/network-policies/gateway-ingress.yaml`](kubernetes/network-policies/gateway-ingress.yaml) - Network policy for F5 access
- [`kubernetes/services/gateway-service.yaml`](kubernetes/services/gateway-service.yaml) - Gateway service definition

## Security Best Practices

1. **Use Separate PKI Hierarchies**
   - Venafi for F5 ↔ API Gateway
   - Consul CA for service mesh

2. **Restrict Trust Boundaries**
   - Use dedicated Venafi intermediate CA
   - Don't trust full enterprise root bundle

3. **Short-Lived Certificates**
   - 30-90 day validity
   - Automated rotation

4. **Strict Validation**
   - Require client certificates
   - Validate SANs and subjects
   - Enable hostname verification

5. **Network Segmentation**
   - NetworkPolicies to restrict F5 access
   - Source IP restrictions

## Certificate Lifecycle

### Issuance
1. Request certificate from Venafi using policy
2. Store in Kubernetes secret (Gateway) or F5 (client)
3. Deploy/apply configuration

### Rotation
1. Automated via Venafi agent (Gateway)
2. CronJob or manual process (F5)
3. Zero-downtime rotation

### Monitoring
- Certificate expiration alerts (15 days)
- TLS handshake failure alerts
- Prometheus metrics

## Troubleshooting

Common issues and solutions:

### Connection Refused
- Check NetworkPolicy allows F5 source IPs
- Verify Gateway service is exposed correctly
- Test connectivity: `telnet gateway-ip 443`

### TLS Handshake Failure
- Verify certificate validity: `openssl x509 -in cert.crt -noout -dates`
- Check certificate chain: `openssl verify -CAfile ca.crt cert.crt`
- Validate SANs match: `openssl x509 -in cert.crt -noout -text | grep DNS`

### Client Certificate Not Required
- Verify Gateway configuration has `require_client_certificate: true`
- Check Venafi CA bundle is mounted correctly
- Test without client cert (should fail)

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for detailed troubleshooting guide.

## Monitoring

### Prometheus Metrics

```promql
# Certificate expiration
(x509_cert_not_after{secret_name="api-gateway-tls"} - time()) / 86400

# TLS handshake failures
rate(envoy_ssl_connection_error{namespace="consul"}[5m])

# mTLS connections
envoy_cluster_ssl_connection_total{cluster_name="local_app"}
```

### Grafana Dashboards

- [`monitoring/grafana/mtls-overview.json`](monitoring/grafana/mtls-overview.json) - mTLS overview dashboard
- [`monitoring/grafana/certificate-expiration.json`](monitoring/grafana/certificate-expiration.json) - Certificate monitoring

## Examples

### Basic Setup
See [`examples/basic/`](examples/basic/) for a minimal working configuration.

### Production Setup
See [`examples/production/`](examples/production/) for production-ready configuration with:
- High availability
- Automated certificate rotation
- Comprehensive monitoring
- Network policies

### Testing
See [`examples/testing/`](examples/testing/) for test configurations and validation scripts.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues or questions:
1. Check [`docs/troubleshooting.md`](docs/troubleshooting.md)
2. Review [`docs/best-practices.md`](docs/best-practices.md)
3. Open an issue in this repository

## License

[Your License Here]

## References

- [Consul API Gateway Documentation](https://developer.hashicorp.com/consul/docs/api-gateway)
- [Venafi Documentation](https://docs.venafi.com/)
- [F5 LTM SSL Profiles](https://techdocs.f5.com/en-us/bigip-15-0-0/big-ip-local-traffic-manager-profiles-reference/ssl-profile.html)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
