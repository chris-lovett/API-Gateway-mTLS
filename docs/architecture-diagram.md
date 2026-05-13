# Detailed Architecture Diagram

## Complete End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    EXTERNAL CLIENT                                          │
│                                                                                             │
│  • Web Browser / Mobile App / API Client                                                   │
│  • HTTPS Request to api.example.com                                                        │
│  • Public CA Certificate (Let's Encrypt, DigiCert)                                         │
└──────────────────────────────────────┬──────────────────────────────────────────────────────┘
                                       │
                                       │ HTTPS (TLS 1.2+)
                                       │ Public CA Certificate
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                  F5 LTM LOAD BALANCER                                       │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                         VIRTUAL SERVER: 10.0.0.100:443                                │ │
│  │                                                                                       │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐    │ │
│  │  │  CLIENT SSL PROFILE (Inbound)                                               │    │ │
│  │  │  • Terminates external TLS                                                  │    │ │
│  │  │  • Server Cert: public-domain.crt (Public CA)                               │    │ │
│  │  │  • Server Key: public-domain.key                                            │    │ │
│  │  │  • Optional: Client cert validation                                         │    │ │
│  │  │  • TLS 1.2+ only                                                            │    │ │
│  │  │  • Strong ciphers: ECDHE-RSA-AES256-GCM-SHA384                             │    │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘    │ │
│  │                                      ↓                                                │ │
│  │                            [Decrypt & Inspect]                                        │ │
│  │                                      ↓                                                │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐    │ │
│  │  │  SERVER SSL PROFILE (Outbound) ← CRITICAL SECURITY BOUNDARY                │    │ │
│  │  │                                                                             │    │ │
│  │  │  CLIENT CERTIFICATE (F5 Identity - Venafi Issued):                         │    │ │
│  │  │  • Cert: f5-client-cert.crt                                                │    │ │
│  │  │  • Key: f5-client-key.key                                                  │    │ │
│  │  │  • CN: f5-load-balancer.example.com                                        │    │ │
│  │  │  • SAN: f5-lb-01.example.com, 10.0.1.10                                    │    │ │
│  │  │  • Issued by: Venafi Intermediate CA                                       │    │ │
│  │  │                                                                             │    │ │
│  │  │  SERVER VALIDATION (API Gateway Certificate):                              │    │ │
│  │  │  • CA Bundle: api-gateway-server-ca.crt (Venafi CA)                        │    │ │
│  │  │  • Peer Cert Mode: REQUIRE                                                 │    │ │
│  │  │  • SNI: api-gateway.consul.svc.cluster.local                               │    │ │
│  │  │  • Hostname Verification: ENABLED                                          │    │ │
│  │  │  • TLS 1.2+ only                                                           │    │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘    │ │
│  │                                      ↓                                                │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐    │ │
│  │  │  POOL: consul-api-gateway-pool                                              │    │ │
│  │  │  • api-gateway-1.openshift.example.com:443                                  │    │ │
│  │  │  • api-gateway-2.openshift.example.com:443                                  │    │ │
│  │  │  • api-gateway-3.openshift.example.com:443                                  │    │ │
│  │  │  • Load Balancing: least-connections-member                                 │    │ │
│  │  │  • Health Monitor: HTTPS with /healthz check                                │    │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘    │ │
│  └───────────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────┬──────────────────────────────────────────────────────┘
                                       │
                                       │ mTLS (Mutual TLS)
                                       │ • F5 → Gateway: Client Cert (Venafi)
                                       │ • Gateway → F5: Server Cert (Venafi)
                                       │ • Both validate each other
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                          OPENSHIFT / KUBERNETES CLUSTER                                     │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                            NETWORK POLICY LAYER                                       │ │
│  │  • Restrict ingress to F5 source IPs only (10.0.1.0/24, 10.0.2.0/24)                │ │
│  │  • Allow egress to backend services and Consul                                       │ │
│  │  • Default deny all other traffic                                                    │ │
│  └───────────────────────────────────────────────────────────────────────────────────────┘ │
│                                       ↓                                                     │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                      CONSUL API GATEWAY (Namespace: consul)                          │ │
│  │                                                                                       │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐    │ │
│  │  │  SERVICE: api-gateway (LoadBalancer/NodePort)                               │    │ │
│  │  │  • External IP: Exposed to F5                                               │    │ │
│  │  │  • Port 443 → 8443 (HTTPS)                                                  │    │ │
│  │  │  • Port 80 → 8080 (HTTP redirect)                                           │    │ │
│  │  │  • Source IP Restrictions: 10.0.1.0/24, 10.0.2.0/24                         │    │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘    │ │
│  │                                      ↓                                                │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐    │ │
│  │  │  GATEWAY PODS (3 replicas with anti-affinity)                               │    │ │
│  │  │                                                                             │    │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────┐     │    │ │
│  │  │  │  TLS LISTENER (Port 8443)                                         │     │    │ │
│  │  │  │                                                                   │     │    │ │
│  │  │  │  SERVER CERTIFICATE (Venafi Issued):                              │     │    │ │
│  │  │  │  • Secret: api-gateway-tls                                        │     │    │ │
│  │  │  │  • CN: api-gateway.consul.svc.cluster.local                       │     │    │ │
│  │  │  │  • SAN: api-gateway.example.com, *.api.example.com                │     │    │ │
│  │  │  │  • Issued by: Venafi Intermediate CA                              │     │    │ │
│  │  │  │                                                                   │     │    │ │
│  │  │  │  CLIENT CERTIFICATE VALIDATION:                                   │     │    │ │
│  │  │  │  • Require Client Certificate: TRUE                               │     │    │ │
│  │  │  │  • CA Bundle: venafi-f5-client-ca (ConfigMap)                     │     │    │ │
│  │  │  │  • Validates F5 client certificate                                │     │    │ │
│  │  │  │  • SAN Matchers: f5-lb-*.example.com, 10.0.1.0/24                │     │    │ │
│  │  │  │  • TLS 1.2+ only                                                  │     │    │ │
│  │  │  │  • Strong ciphers only                                            │     │    │ │
│  │  │  └───────────────────────────────────────────────────────────────────┘     │    │ │
│  │  │                                      ↓                                      │    │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────┐     │    │ │
│  │  │  │  HTTPROUTE PROCESSING                                             │     │    │ │
│  │  │  │  • Path-based routing: /api/v1 → backend-service                  │     │    │ │
│  │  │  │  • Header modification: X-Forwarded-Proto, X-Gateway              │     │    │ │
│  │  │  │  • Traffic splitting: 90% stable, 10% canary                      │     │    │ │
│  │  │  │  • Rate limiting (optional)                                       │     │    │ │
│  │  │  └───────────────────────────────────────────────────────────────────┘     │    │ │
│  │  │                                      ↓                                      │    │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────┐     │    │ │
│  │  │  │  CONSUL CONNECT SIDECAR (Envoy)                                   │     │    │ │
│  │  │  │  • Automatic mTLS to backend services                             │     │    │ │
│  │  │  │  • Certificate: Auto-issued by Consul CA                          │     │    │ │
│  │  │  │  • Separate from Venafi PKI                                       │     │    │ │
│  │  │  │  • Service mesh encryption                                        │     │    │ │
│  │  │  └───────────────────────────────────────────────────────────────────┘     │    │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘    │ │
│  └───────────────────────────────────────────────────────────────────────────────────────┘ │
│                                       ↓                                                     │
│                                       │ Consul Connect mTLS                                 │
│                                       │ (Consul CA - Automatic)                             │
│                                       │                                                     │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                    SERVICE INTENTIONS (Authorization Layer)                           │ │
│  │  • api-gateway → backend-service: ALLOW (with L7 permissions)                        │ │
│  │  • Paths: /api/v1/*, /health, /metrics                                               │ │
│  │  • Methods: GET, POST, PUT, DELETE                                                   │ │
│  │  • All other sources: DENY                                                           │ │
│  └───────────────────────────────────────────────────────────────────────────────────────┘ │
│                                       ↓                                                     │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                    BACKEND SERVICE (Namespace: default)                               │ │
│  │                                                                                       │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐    │ │
│  │  │  SERVICE: backend-service (ClusterIP)                                       │    │ │
│  │  │  • Port 8080                                                                │    │ │
│  │  │  • Selector: app=backend                                                    │    │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘    │ │
│  │                                      ↓                                                │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐    │ │
│  │  │  BACKEND PODS (3 replicas with HPA)                                         │    │ │
│  │  │                                                                             │    │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────┐     │    │ │
│  │  │  │  CONSUL CONNECT SIDECAR (Envoy)                                   │     │    │ │
│  │  │  │  • Receives mTLS traffic from API Gateway sidecar                 │     │    │ │
│  │  │  │  • Certificate: Auto-issued by Consul CA                          │     │    │ │
│  │  │  │  • Validates API Gateway identity                                 │     │    │ │
│  │  │  │  • Enforces Service Intentions                                    │     │    │ │
│  │  │  │  • Metrics: Merged with app metrics on port 9090                  │     │    │ │
│  │  │  └───────────────────────────────────────────────────────────────────┘     │    │ │
│  │  │                                      ↓                                      │    │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────┐     │    │ │
│  │  │  │  APPLICATION CONTAINER                                            │     │    │ │
│  │  │  │  • Receives plain HTTP from sidecar (localhost:8080)              │     │    │ │
│  │  │  │  • No TLS configuration needed                                    │     │    │ │
│  │  │  │  • Business logic processing                                      │     │    │ │
│  │  │  │  • Health checks: /health, /ready                                 │     │    │ │
│  │  │  └───────────────────────────────────────────────────────────────────┘     │    │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘    │ │
│  └───────────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════════════════════
                                    CERTIFICATE HIERARCHY
═══════════════════════════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              VENAFI PKI (Edge Ingress)                                      │
│                                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  Venafi Root CA                                                                     │   │
│  │  • Enterprise root certificate authority                                            │   │
│  │  • Validity: 10+ years                                                              │   │
│  └──────────────────────────────────────┬──────────────────────────────────────────────┘   │
│                                         │                                                   │
│                                         ▼                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  Venafi Intermediate CA (Ingress)                                                   │   │
│  │  • Dedicated for F5 ↔ API Gateway mTLS                                              │   │
│  │  • Validity: 5 years                                                                │   │
│  │  • Policy: consul-api-gateway-server, f5-client-certificate                         │   │
│  └──────────────────────────────┬───────────────────────────────┬───────────────────────┘   │
│                                 │                               │                           │
│                                 ▼                               ▼                           │
│  ┌──────────────────────────────────────────┐  ┌──────────────────────────────────────┐   │
│  │  API Gateway Server Certificate          │  │  F5 Client Certificate               │   │
│  │  • CN: api-gateway.consul.svc...         │  │  • CN: f5-load-balancer.example.com  │   │
│  │  • SAN: api-gateway.example.com          │  │  • SAN: f5-lb-01.example.com         │   │
│  │  • SAN: *.api.example.com                │  │  • SAN: 10.0.1.10                    │   │
│  │  • Key Usage: serverAuth                 │  │  • Key Usage: clientAuth             │   │
│  │  • Validity: 90 days                     │  │  • Validity: 90 days                 │   │
│  │  • Auto-rotation: 15 days before expiry  │  │  • Auto-rotation: 15 days before     │   │
│  │  • Storage: Kubernetes Secret            │  │  • Storage: F5 certificate store     │   │
│  └──────────────────────────────────────────┘  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              CONSUL PKI (Service Mesh)                                      │
│                                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  Consul Root CA                                                                     │   │
│  │  • Built-in Consul CA or Vault                                                      │   │
│  │  • Validity: 10 years                                                               │   │
│  └──────────────────────────────────────┬──────────────────────────────────────────────┘   │
│                                         │                                                   │
│                                         ▼                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  Consul Intermediate CA                                                             │   │
│  │  • Automatic management by Consul                                                   │   │
│  │  • Validity: 1 year                                                                 │   │
│  └──────────────────────────────┬───────────────────────────────┬───────────────────────┘   │
│                                 │                               │                           │
│                                 ▼                               ▼                           │
│  ┌──────────────────────────────────────────┐  ┌──────────────────────────────────────┐   │
│  │  API Gateway Sidecar Certificate         │  │  Backend Service Certificate         │   │
│  │  • SPIFFE ID: spiffe://consul/...        │  │  • SPIFFE ID: spiffe://consul/...    │   │
│  │  • Auto-issued by Consul                 │  │  • Auto-issued by Consul             │   │
│  │  • Validity: 72 hours (default)          │  │  • Validity: 72 hours (default)      │   │
│  │  • Auto-rotation: Continuous             │  │  • Auto-rotation: Continuous         │   │
│  │  • Storage: Envoy memory                 │  │  • Storage: Envoy memory             │   │
│  └──────────────────────────────────────────┘  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════════════════════
                                    SECURITY BOUNDARIES
═══════════════════════════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  BOUNDARY 1: External → F5                                                                  │
│  • Protocol: HTTPS (TLS 1.2+)                                                               │
│  • Certificates: Public CA (Let's Encrypt, DigiCert)                                        │
│  • Authentication: Optional client certificates                                             │
│  • Purpose: Secure external client connections                                              │
│  • Trust: Public certificate authorities                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  BOUNDARY 2: F5 → API Gateway (PRIMARY SECURITY BOUNDARY)                                   │
│  • Protocol: mTLS (Mutual TLS 1.2+)                                                         │
│  • Certificates: Venafi-issued (dedicated intermediate CA)                                  │
│  • Authentication: Mutual - both sides validate                                             │
│  • Purpose: Authenticated north-south traffic                                               │
│  • Trust: Venafi Intermediate CA (Ingress)                                                  │
│  • Network: Restricted by NetworkPolicy to F5 IPs only                                      │
│  • Validation: Strict (require mode, hostname verification, SAN matching)                   │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  BOUNDARY 3: API Gateway → Service Mesh                                                     │
│  • Protocol: mTLS (Consul Connect)                                                          │
│  • Certificates: Consul CA (automatic)                                                      │
│  • Authentication: Automatic via Consul                                                     │
│  • Purpose: Service-to-service security                                                     │
│  • Trust: Consul CA (separate from Venafi)                                                  │
│  • Authorization: Consul Service Intentions (L7 policies)                                   │
│  • Rotation: Automatic (72-hour TTL by default)                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════════════════════
                                    TRAFFIC FLOW EXAMPLE
═══════════════════════════════════════════════════════════════════════════════════════════════

1. External Client Request
   └─> HTTPS GET https://api.example.com/api/v1/users
       • TLS handshake with F5 using public CA cert
       • Client may present certificate (optional)

2. F5 Processing
   └─> Terminates external TLS
   └─> Inspects request (WAF, rate limiting)
   └─> Initiates new mTLS connection to API Gateway
       • Presents f5-client-cert.crt (Venafi)
       • Validates api-gateway server cert (Venafi)
       • SNI: api-gateway.consul.svc.cluster.local

3. API Gateway Processing
   └─> Validates F5 client certificate
       • Checks against venafi-f5-client-ca
       • Verifies SAN matches f5-lb-*.example.com
   └─> Routes based on HTTPRoute
       • Path /api/v1/users → backend-service
       • Adds headers: X-Forwarded-Proto, X-Gateway
   └─> Consul Connect sidecar initiates mTLS to backend
       • Uses Consul-issued certificate
       • Validates backend service identity

4. Backend Service Processing
   └─> Consul sidecar validates API Gateway identity
   └─> Checks Service Intentions
       • api-gateway → backend-service: ALLOW
       • Path /api/v1/* with GET method: ALLOW
   └─> Forwards plain HTTP to application container
   └─> Application processes request
   └─> Returns response through same path

5. Response Flow
   └─> Backend → API Gateway (Consul Connect mTLS)
   └─> API Gateway → F5 (Venafi mTLS)
   └─> F5 → External Client (Public CA TLS)


═══════════════════════════════════════════════════════════════════════════════════════════════
                                    MONITORING & OBSERVABILITY
═══════════════════════════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  F5 Metrics                                                                                 │
│  • SSL handshake statistics                                                                 │
│  • Connection counts (client-side, server-side)                                             │
│  • Certificate expiration monitoring                                                        │
│  • Virtual server performance                                                               │
│  • Pool member health                                                                       │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  API Gateway Metrics (Prometheus)                                                           │
│  • envoy_ssl_connection_error - TLS handshake failures                                      │
│  • envoy_cluster_ssl_connection_total - mTLS connections                                    │
│  • gateway_api_http_request_duration - Request latency                                      │
│  • x509_cert_not_after - Certificate expiration                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  Service Mesh Metrics (Consul)                                                              │
│  • consul_connect_ca_leaf_cert_expiry_seconds - Cert expiration                             │
│  • envoy_cluster_upstream_rq_total - Service-to-service requests                            │
│  • consul_intention_allow_total - Allowed connections                                       │
│  • consul_intention_deny_total - Denied connections                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────┘