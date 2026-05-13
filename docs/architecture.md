# Architecture: F5 LTM to Consul API Gateway mTLS

## Overview

This document describes the end-to-end architecture for securing traffic from F5 Load Balancers to Consul API Gateway using mutual TLS (mTLS) with Venafi-issued certificates.

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                      External Client                             │
│                   (HTTPS - Public CA Cert)                       │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                        F5 LTM Load Balancer                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Client SSL Profile (Inbound)                               │ │
│  │  - Terminate external TLS                                  │ │
│  │  - Public CA certificate                                   │ │
│  │  - Optional: Client cert validation                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Server SSL Profile (Outbound) ← SECURITY BOUNDARY         │ │
│  │  - Client Cert: F5 identity (Venafi-issued)               │ │
│  │  - Server Validation: API Gateway cert (Venafi CA)        │ │
│  │  - SNI: api-gateway.consul.svc.cluster.local              │ │
│  │  - Peer Cert Validation: ENABLED                          │ │
│  └────────────────────────────────────────────────────────────┘ │
└────────────────────────────┬─────────────────────────────────────┘
                             │ mTLS (Venafi PKI)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│              Consul API Gateway (OpenShift)                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ TLS Listener                                               │ │
│  │  - Server Cert: Gateway identity (Venafi-issued)           │ │
│  │  - Require Client Certificate: TRUE                        │ │
│  │  - Validate Client Cert: Venafi CA bundle                  │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Consul Connect Sidecar (Envoy)                             │ │
│  │  - Separate mTLS for service mesh                          │ │
│  │  - Consul CA (not Venafi)                                  │ │
│  └────────────────────────────────────────────────────────────┘ │
└────────────────────────────┬─────────────────────────────────────┘
                             │ Consul Connect mTLS
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Backend Services (OpenShift)                  │
│  - Consul Connect automatic mTLS                                 │
│  - Consul Intentions for authorization                           │
└──────────────────────────────────────────────────────────────────┘
```

## Trust Boundaries

### Boundary 1: External → F5
- **Protocol**: HTTPS
- **Certificates**: Public CA (Let's Encrypt, DigiCert, etc.)
- **Authentication**: Optional client certificates
- **Purpose**: Secure external client connections

### Boundary 2: F5 → API Gateway (PRIMARY FOCUS)
- **Protocol**: mTLS
- **Certificates**: Venafi-issued
- **Authentication**: Mutual - both sides validate
- **Purpose**: Authenticated north-south traffic

### Boundary 3: API Gateway → Service Mesh
- **Protocol**: mTLS (Consul Connect)
- **Certificates**: Consul CA
- **Authentication**: Automatic via Consul
- **Purpose**: Service-to-service security

## Certificate Strategy

### Separate PKI Hierarchies

```
Venafi PKI (Edge Ingress)
├── Venafi Root CA
│   └── Venafi Intermediate CA (Ingress)
│       ├── API Gateway Server Certificate
│       │   CN: api-gateway.consul.svc.cluster.local
│       │   SAN: api-gateway.example.com, *.api.example.com
│       └── F5 Client Certificate
│           CN: f5-load-balancer.example.com
│           SAN: f5-lb-01.example.com, 10.0.1.10

Consul PKI (Service Mesh)
├── Consul Root CA
│   └── Consul Intermediate CA
│       ├── API Gateway Sidecar Certificate (auto-issued)
│       └── Backend Service Certificates (auto-issued)
```

### Why Separate PKI?

1. **Security Isolation**: Compromise of edge doesn't affect mesh
2. **Lifecycle Management**: Different rotation policies
3. **Trust Scoping**: Minimal trust boundaries
4. **Operational Clarity**: Clear ownership and responsibility

## Traffic Flow

### 1. External Client Request

```
Client → F5 LTM
- Client initiates HTTPS connection
- F5 terminates TLS using public CA certificate
- Optional: F5 validates client certificate
- F5 decrypts and inspects traffic
```

### 2. F5 to API Gateway (mTLS)

```
F5 → API Gateway
- F5 initiates new TLS connection
- F5 presents client certificate (Venafi-issued)
- API Gateway presents server certificate (Venafi-issued)
- Both sides validate certificates against Venafi CA
- SNI: api-gateway.consul.svc.cluster.local
- Mutual authentication successful
```

### 3. API Gateway to Backend Service

```
API Gateway → Backend Service
- Consul Connect automatic mTLS
- Envoy sidecars handle encryption
- Consul CA issues certificates
- Consul Intentions enforce authorization
```

## Component Details

### F5 LTM Configuration

#### Client SSL Profile (Inbound)
```
Purpose: Terminate external client TLS
Certificate: Public CA certificate
Key: Private key for public certificate
Client Auth: Optional
```

#### Server SSL Profile (Outbound)
```
Purpose: mTLS to API Gateway
Client Certificate: F5 identity (Venafi)
Client Key: F5 private key
Server CA Bundle: Venafi CA for Gateway validation
Peer Cert Mode: Require
SNI: api-gateway.consul.svc.cluster.local
```

#### Virtual Server
```
Frontend: External IP:443
Backend Pool: API Gateway endpoints
Client Profile: external-client-ssl
Server Profile: f5-to-consul-gateway
```

### Consul API Gateway

#### Gateway Resource
```yaml
Listener:
  - Port: 443
  - Protocol: HTTPS
  - TLS Mode: Terminate
  - Server Certificate: Venafi-issued
  - Client Certificate: Required
  - Client CA: Venafi CA bundle
```

#### TLS Configuration
```
Server Certificate: api-gateway-tls secret
Client Validation: venafi-f5-client-ca ConfigMap
Require Client Cert: true
TLS Min Version: 1.2
Cipher Suites: Strong ciphers only
```

### OpenShift Networking

#### Service Exposure Options

**Option A: Direct Exposure (Recommended)**
```yaml
Service Type: LoadBalancer or NodePort
Direct connection from F5 to Gateway pods
No intermediate TLS termination
Preserves mTLS end-to-end
```

**Option B: Passthrough Route**
```yaml
Route Type: Passthrough
No TLS termination at router
F5 connects through OpenShift router
mTLS preserved
```

## Security Controls

### Network Layer
- NetworkPolicy restricts access to F5 source IPs only
- Service mesh policies via Consul Intentions
- Pod security policies/standards

### Certificate Layer
- Short-lived certificates (30-90 days)
- Automated rotation via Venafi
- Strict validation (no ignore/optional modes)
- SAN/subject constraints

### Application Layer
- Consul Intentions for L7 authorization
- HTTP method/path restrictions
- Rate limiting at API Gateway

## High Availability

### F5 LTM
- Active-Active or Active-Standby pair
- Shared virtual server configuration
- Certificate synchronization

### Consul API Gateway
- Multiple replicas (3+ recommended)
- Pod anti-affinity rules
- Health checks and readiness probes

### Backend Services
- Multiple replicas per service
- Consul health checking
- Automatic failover via service mesh

## Monitoring and Observability

### Metrics Collection
```
F5 → Prometheus
- SSL handshake stats
- Connection counts
- Certificate expiration

API Gateway → Prometheus
- Envoy metrics
- Request rates
- TLS handshake failures

Service Mesh → Prometheus
- Service-to-service metrics
- mTLS connection stats
- Intention denials
```

### Logging
```
F5 → Syslog/Splunk
- Access logs
- SSL handshake events
- Certificate validation failures

API Gateway → OpenShift Logging
- Request logs
- TLS errors
- Client certificate details

Service Mesh → Consul/Envoy Logs
- Connection events
- Authorization decisions
```

### Alerting
```
Certificate Expiration < 15 days
TLS Handshake Failure Rate > threshold
Connection Refused errors
Certificate validation failures
```

## Disaster Recovery

### Certificate Loss
1. Request new certificates from Venafi
2. Update F5 configuration
3. Update Kubernetes secrets
4. Rolling restart of Gateway pods

### F5 Failure
1. Failover to standby F5
2. Certificates already synchronized
3. No Gateway changes needed

### API Gateway Failure
1. Kubernetes recreates pods automatically
2. Certificates mounted from secrets
3. F5 health checks detect and route around

### Venafi Outage
1. Existing certificates continue to work
2. Rotation delayed until Venafi available
3. Monitor certificate expiration closely

## Compliance and Audit

### Certificate Audit Trail
- Venafi logs all certificate operations
- Kubernetes audit logs for secret access
- F5 logs certificate usage

### Access Audit
- F5 logs all client connections
- API Gateway logs all requests
- Consul logs service-to-service calls

### Compliance Requirements
- TLS 1.2+ only
- Strong cipher suites
- Certificate rotation < 90 days
- Mutual authentication enforced
- Network segmentation

## Performance Considerations

### TLS Overhead
- F5 hardware acceleration for TLS
- Envoy efficient TLS implementation
- Connection pooling and reuse

### Certificate Validation
- OCSP stapling for revocation checking
- CRL caching
- Validation result caching

### Latency Impact
```
External Client → F5: ~5-10ms (TLS handshake)
F5 → API Gateway: ~5-10ms (mTLS handshake)
API Gateway → Backend: ~1-2ms (mesh mTLS)
Total TLS overhead: ~15-25ms
```

## Future Enhancements

### Short-Term
- Automated certificate rotation for F5
- Enhanced monitoring dashboards
- Automated testing framework

### Long-Term
- SPIFFE/SPIRE integration
- Hardware security module (HSM) integration
- Multi-region deployment
- Zero-trust network architecture

## References

- [Consul API Gateway Documentation](https://developer.hashicorp.com/consul/docs/api-gateway)
- [Venafi Trust Protection Platform](https://docs.venafi.com/)
- [F5 SSL Profile Reference](https://techdocs.f5.com/en-us/bigip-15-0-0/big-ip-local-traffic-manager-profiles-reference/ssl-profile.html)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Envoy TLS Configuration](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/security/ssl)