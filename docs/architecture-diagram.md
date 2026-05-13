# API Gateway mTLS Architecture

## At a Glance

```mermaid
flowchart TB
    client[External Client<br/>Browser / Mobile / API Client]
    f5[F5 Load Balancer<br/>Public TLS termination<br/>WAF / inspection]
    gateway[Consul API Gateway<br/>Venafi server cert<br/>Validates F5 client cert]
    mesh[Consul Connect Service Mesh<br/>Automatic mTLS]
    backend[Backend Service<br/>Plain HTTP in app container]

    client -->|HTTPS<br/>Public CA| f5
    f5 -->|mTLS<br/>Venafi PKI| gateway
    gateway -->|mTLS<br/>Consul CA| mesh
    mesh --> backend
```

## Why This Architecture Exists

This architecture separates external ingress security from internal service-to-service security:

- **External Client → F5** uses standard HTTPS with a public CA certificate.
- **F5 → API Gateway** uses **mutual TLS (mTLS)** with **Venafi-issued certificates**.
- **API Gateway → Backend Service** uses **Consul Connect mTLS** with **Consul-issued identities**.
- **Backend applications** stay simple by receiving plain HTTP only from their local sidecar.

## Trust Boundaries

| Boundary | Connection | TLS Mode | Trust Source | Purpose |
|---|---|---|---|---|
| 1 | External Client → F5 | HTTPS | Public CA | Secure public ingress |
| 2 | F5 → API Gateway | mTLS | Venafi PKI | Authenticated north-south traffic |
| 3 | API Gateway → Backend | mTLS | Consul CA | Service-to-service encryption |

> [!IMPORTANT]
> The primary security boundary is **F5 → API Gateway**. This is where mutual authentication is enforced using Venafi-issued certificates.

## Request Flow

1. **Client request**  
   A client sends `HTTPS` traffic to `api.example.com` using a certificate trusted by a public CA.

2. **F5 processing**  
   F5 terminates external TLS, performs inspection or policy enforcement, and opens a new **mTLS** connection to the API Gateway.

3. **Gateway authentication and routing**  
   The API Gateway validates the F5 client certificate, applies `HTTPRoute` rules, and forwards traffic toward the backend service.

4. **Service mesh transport**  
   Consul Connect sidecars establish **mTLS** between the gateway and backend service.

5. **Backend handling**  
   The backend sidecar forwards plain HTTP to the local application container.

6. **Response path**  
   The response returns over the same layers in reverse: backend mesh → gateway → F5 → external client.

## Core Components

### External Client
- Web browser, mobile app, or API client
- Connects to `api.example.com`
- Uses standard HTTPS
- May optionally present a client certificate if required by edge policy

### F5 Load Balancer
- Terminates public TLS
- Presents the public-facing server certificate
- Applies inspection, WAF, rate limiting, or other edge controls
- Presents an **F5 client certificate** to the API Gateway
- Validates the API Gateway server certificate
- Forwards traffic only to healthy API Gateway pool members

### Consul API Gateway
- Exposes HTTPS listener for inbound traffic from F5
- Presents a **Venafi-issued server certificate**
- Requires and validates the F5 client certificate
- Applies `HTTPRoute` path and header rules
- Uses Consul Connect sidecar for service mesh communication

### Consul Service Mesh
- Establishes automatic mTLS between workloads
- Issues short-lived workload identities
- Enforces service intentions and authorization rules
- Keeps service-to-service encryption separate from ingress PKI

### Backend Service
- Receives traffic through a Consul sidecar
- Benefits from mesh identity and authorization controls
- Receives plain HTTP from `localhost` sidecar traffic only
- Does not need to manage external TLS directly

## Certificate Model

The environment uses **two separate PKI domains**:

1. **Venafi PKI** for ingress trust between F5 and API Gateway
2. **Consul PKI** for east-west service mesh trust

### Venafi PKI: Edge Ingress Trust

| Certificate | Used By | Purpose | Rotation / Lifetime | Storage |
|---|---|---|---|---|
| Public server certificate | F5 | External HTTPS for `api.example.com` | Per public CA policy | F5 certificate store |
| F5 client certificate | F5 | Authenticate F5 to API Gateway | Rotated before expiry | F5 certificate store |
| API Gateway server certificate | API Gateway | Authenticate API Gateway to F5 | Rotated before expiry | Kubernetes Secret |

Typical validation on this boundary includes:

- Client certificate required
- Hostname verification enabled
- SAN / identity matching enforced
- TLS 1.2+ only
- Strong cipher suites only

### Consul PKI: Service Mesh Trust

| Certificate | Used By | Purpose | Rotation / Lifetime | Storage |
|---|---|---|---|---|
| Gateway sidecar certificate | API Gateway sidecar | Mesh identity | Short-lived / automatic | Envoy memory |
| Backend sidecar certificate | Backend sidecar | Mesh identity | Short-lived / automatic | Envoy memory |

This PKI domain is intentionally separate from the Venafi ingress PKI.

## Policy and Routing Summary

### Network policy
- Restrict ingress to trusted F5 source IP ranges only
- Allow egress only to required backend services and Consul components
- Deny other traffic by default

### Gateway routing
- Path-based routing such as `/api/v1/* → backend-service`
- Header mutation such as `X-Forwarded-Proto` or `X-Gateway`
- Optional traffic splitting for canary releases
- Optional rate limiting and edge policy enforcement

### Service intentions
- Explicitly allow `api-gateway → backend-service`
- Restrict paths and methods where needed
- Deny all unspecified sources by default

## Observability

### F5
- TLS handshake metrics
- Client-side and server-side connection counts
- Certificate expiration monitoring
- Virtual server and pool health

### API Gateway / Envoy
- TLS handshake failures
- Upstream TLS connection totals
- Request duration and latency metrics
- Certificate expiration metrics

### Consul Service Mesh
- Leaf certificate expiry metrics
- Service-to-service request totals
- Intention allow / deny counters

## Operational Notes

> [!NOTE]
> The backend application does **not** terminate TLS directly. TLS is terminated or enforced by infrastructure layers: F5 at the edge, API Gateway for ingress mTLS, and Consul sidecars for service mesh mTLS.

> [!TIP]
> When debugging connectivity, check the failing boundary first:
>
> - **External connectivity issues** → F5 public TLS and DNS
> - **Ingress authentication issues** → F5 ↔ API Gateway Venafi mTLS
> - **Backend communication issues** → Consul Connect mTLS and intentions

<details>
<summary>Implementation details preserved from the original design</summary>

### F5 to API Gateway boundary
- F5 acts as the client when connecting to the API Gateway
- API Gateway acts as the server on the ingress mTLS boundary
- F5 validates the API Gateway certificate against the Venafi CA bundle
- API Gateway validates the F5 client certificate against the trusted Venafi client CA bundle
- SNI and hostname verification should remain enabled where supported

### API Gateway service shape
- Service may be exposed using `LoadBalancer` or `NodePort` patterns depending on platform requirements
- HTTPS listener commonly maps `443 → 8443`
- Optional HTTP redirect listener commonly maps `80 → 8080`

### Backend service shape
- Backend service is typically exposed internally as `ClusterIP`
- Application container commonly listens on port `8080`
- Health endpoints may include `/health` and `/ready`

</details>
