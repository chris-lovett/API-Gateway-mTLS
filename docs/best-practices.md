# Security Best Practices

## Certificate Management

### 1. Use Separate PKI Hierarchies

**DO**: Maintain separate certificate authorities for different trust boundaries
```
✓ Venafi PKI for F5 ↔ API Gateway
✓ Consul CA for service mesh
✓ Public CA for external clients
```

**DON'T**: Mix certificate authorities across boundaries
```
✗ Using Venafi certs for service mesh
✗ Using Consul CA for F5 client certs
✗ Reusing same cert for multiple purposes
```

### 2. Restrict Trust Boundaries

**DO**: Use dedicated intermediate CAs
```bash
# F5 trusts only Venafi intermediate CA for API Gateway
ca-file venafi-ingress-intermediate-ca.crt

# API Gateway trusts only Venafi intermediate CA for F5 clients
validation_context:
  trusted_ca:
    filename: /etc/venafi-ca/f5-client-ca.crt
```

**DON'T**: Trust full enterprise root CA bundle
```bash
# ✗ Too broad - trusts everything
ca-file enterprise-root-ca-bundle.crt
```

### 3. Use Short-Lived Certificates

**Recommended Validity Periods**:
- F5 Client Certificate: 30-90 days
- API Gateway Server Certificate: 30-90 days
- Service Mesh Certificates: 72 hours (Consul default)

**Benefits**:
- Reduced impact of compromise
- Forces regular rotation testing
- Aligns with modern security practices

### 4. Enforce Strong TLS Configuration

**Minimum TLS Version**: TLS 1.2
```bash
# F5
tm-options { no-tlsv1 no-tlsv1.1 }

# API Gateway
tls_params:
  tls_minimum_protocol_version: TLSv1_2
```

**Cipher Suites**: Use only strong ciphers
```bash
# F5
ciphers "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256"

# API Gateway
cipher_suites:
  - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
  - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
```

### 5. Validate Certificates Strictly

**DO**: Require and validate certificates
```bash
# F5
peer-cert-mode require
ca-file api-gateway-server-ca.crt
server-name api-gateway.consul.svc.cluster.local

# API Gateway
require_client_certificate: true
validation_context:
  trusted_ca: { filename: /etc/venafi-ca/ca.crt }
```

**DON'T**: Use permissive modes
```bash
# ✗ Never use these
peer-cert-mode ignore
peer-cert-mode optional
require_client_certificate: false
```

## Network Security

### 1. Implement Network Segmentation

**NetworkPolicy Example**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-gateway-ingress-f5-only
spec:
  podSelector:
    matchLabels:
      app: api-gateway
  policyTypes:
    - Ingress
  ingress:
    - from:
        - ipBlock:
            cidr: 10.0.1.0/24  # F5 subnet only
      ports:
        - protocol: TCP
          port: 8443
```

### 2. Use Source IP Restrictions

**F5 Virtual Server**:
```bash
# Restrict to known client networks
tmsh modify ltm virtual consul-api-gateway-vs \
  source 0.0.0.0/0 \
  source-address-translation { type automap }
```

**OpenShift Service**:
```yaml
spec:
  loadBalancerSourceRanges:
    - 10.0.1.0/24  # F5 subnet
    - 10.0.2.0/24  # Backup F5 subnet
```

### 3. Avoid Double TLS Termination

**DO**: Use passthrough or direct exposure
```yaml
# Option A: Direct Service exposure
apiVersion: v1
kind: Service
spec:
  type: LoadBalancer

# Option B: Passthrough Route
apiVersion: route.openshift.io/v1
kind: Route
spec:
  tls:
    termination: passthrough
```

**DON'T**: Terminate TLS at OpenShift Router
```yaml
# ✗ This breaks F5 mTLS
spec:
  tls:
    termination: edge
```

## Certificate Lifecycle

### 1. Automate Certificate Rotation

**Venafi Agent for API Gateway**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: venafi-agent
spec:
  template:
    spec:
      containers:
        - name: venafi-agent
          env:
            - name: RENEW_BEFORE_DAYS
              value: "15"  # Renew 15 days before expiration
```

**CronJob for F5 Certificates**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: f5-cert-rotation
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
```

### 2. Monitor Certificate Expiration

**Prometheus Alert**:
```yaml
- alert: CertificateExpiringSoon
  expr: (x509_cert_not_after - time()) / 86400 < 15
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "Certificate expires in {{ $value }} days"
```

### 3. Test Rotation Procedures

**Regular Testing**:
- Monthly rotation dry-runs
- Automated rotation testing in non-prod
- Documented rollback procedures

## Access Control

### 1. Use Consul Intentions

**Explicit Allow Model**:
```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: api-gateway-to-backend
spec:
  destination:
    name: backend
  sources:
    - name: api-gateway
      action: allow
      permissions:
        - action: allow
          http:
            pathPrefix: /api
            methods: ["GET", "POST"]
```

### 2. Implement Least Privilege

**RBAC for Certificate Management**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cert-manager
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["api-gateway-tls"]
    verbs: ["get", "update"]
```

### 3. Audit Certificate Access

**Enable Kubernetes Audit Logging**:
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
    namespaces: ["consul"]
```

## Operational Security

### 1. Secure Certificate Storage

**F5**:
- Store private keys in encrypted partitions
- Use HSM for high-security environments
- Restrict tmsh access

**Kubernetes**:
- Use encrypted secrets (etcd encryption)
- Limit secret access via RBAC
- Consider external secret management (Vault)

### 2. Implement Defense in Depth

**Multiple Security Layers**:
1. Network segmentation (NetworkPolicy)
2. mTLS authentication (Venafi certs)
3. Application authorization (Intentions)
4. Rate limiting (API Gateway)
5. WAF rules (F5)

### 3. Regular Security Audits

**Monthly Reviews**:
- Certificate inventory and expiration
- Access logs for anomalies
- TLS configuration compliance
- Network policy effectiveness

**Quarterly Reviews**:
- Penetration testing
- Certificate authority audit
- Incident response procedures
- Disaster recovery testing

## Monitoring and Alerting

### 1. Monitor TLS Health

**Key Metrics**:
```promql
# Handshake failures
rate(envoy_ssl_connection_error[5m]) > 0.1

# Certificate expiration
(x509_cert_not_after - time()) / 86400 < 15

# Connection counts
envoy_cluster_ssl_connection_total
```

### 2. Alert on Security Events

**Critical Alerts**:
- Certificate expiration < 7 days
- TLS handshake failure rate > 1%
- Unauthorized access attempts
- Certificate validation failures

### 3. Log Security Events

**What to Log**:
- All certificate operations
- TLS handshake failures
- Client certificate details
- Authorization decisions

## Compliance

### 1. Meet Regulatory Requirements

**Common Standards**:
- PCI DSS: TLS 1.2+, strong ciphers
- HIPAA: Encryption in transit
- SOC 2: Certificate lifecycle management
- ISO 27001: Access control and monitoring

### 2. Document Security Controls

**Required Documentation**:
- Certificate issuance procedures
- Rotation procedures
- Incident response plans
- Access control policies

### 3. Maintain Audit Trail

**Audit Requirements**:
- Certificate request/issuance logs
- Configuration change logs
- Access logs
- Security event logs

## Common Pitfalls to Avoid

### 1. Certificate Mismanagement

**DON'T**:
- ✗ Use same certificate for multiple purposes
- ✗ Share private keys between systems
- ✗ Ignore certificate expiration warnings
- ✗ Use self-signed certs in production

### 2. Weak TLS Configuration

**DON'T**:
- ✗ Allow TLS 1.0 or 1.1
- ✗ Use weak cipher suites
- ✗ Disable certificate validation
- ✗ Skip hostname verification

### 3. Poor Network Security

**DON'T**:
- ✗ Allow unrestricted network access
- ✗ Expose services without NetworkPolicy
- ✗ Trust all source IPs
- ✗ Skip network segmentation

### 4. Inadequate Monitoring

**DON'T**:
- ✗ Ignore certificate expiration
- ✗ Skip TLS handshake monitoring
- ✗ Disable security logging
- ✗ Lack alerting on failures

## Security Checklist

### Pre-Deployment
- [ ] Certificates issued from Venafi
- [ ] Separate PKI hierarchies configured
- [ ] TLS 1.2+ enforced
- [ ] Strong cipher suites configured
- [ ] Certificate validation enabled
- [ ] NetworkPolicies defined
- [ ] Monitoring configured
- [ ] Alerts defined

### Post-Deployment
- [ ] mTLS verified end-to-end
- [ ] Certificate expiration monitored
- [ ] Access logs reviewed
- [ ] Security events alerted
- [ ] Rotation procedures tested
- [ ] Documentation updated
- [ ] Team trained

### Ongoing
- [ ] Monthly certificate review
- [ ] Quarterly security audit
- [ ] Regular rotation testing
- [ ] Incident response drills
- [ ] Compliance verification
- [ ] Documentation maintenance

## References

- [NIST TLS Guidelines](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf)
- [OWASP TLS Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Protection_Cheat_Sheet.html)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Venafi Security Best Practices](https://docs.venafi.com/)