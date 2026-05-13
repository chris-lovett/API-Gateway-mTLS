#!/bin/bash
#
# Request API Gateway Server Certificate from Venafi
#
# Usage: ./request-gateway-cert.sh
#
# Environment Variables:
#   VENAFI_URL       - Venafi TPP URL (default: https://venafi.example.com/vedsdk)
#   VENAFI_ZONE      - Venafi policy zone (default: \VED\Policy\Consul\API-Gateway-Server)
#   VENAFI_TOKEN     - Venafi access token (required)
#   CERT_CN          - Certificate common name (default: api-gateway.consul.svc.cluster.local)
#   CERT_SAN_DNS     - Additional DNS SANs (comma-separated)
#   OUTPUT_DIR       - Output directory for certificates (default: ./certs)
#

set -e

# Configuration
VENAFI_URL="${VENAFI_URL:-https://venafi.example.com/vedsdk}"
VENAFI_ZONE="${VENAFI_ZONE:-\\VED\\Policy\\Consul\\API-Gateway-Server}"
CERT_CN="${CERT_CN:-api-gateway.consul.svc.cluster.local}"
CERT_SAN_DNS="${CERT_SAN_DNS:-api-gateway.example.com,*.api.example.com}"
OUTPUT_DIR="${OUTPUT_DIR:-./certs}"
VENAFI_CA_BUNDLE="${VENAFI_CA_BUNDLE:-/etc/ssl/venafi-ca-bundle.pem}"

# Check required variables
if [ -z "$VENAFI_TOKEN" ]; then
    echo "Error: VENAFI_TOKEN environment variable is required"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "=== Requesting API Gateway Server Certificate from Venafi ==="
echo "Venafi URL: $VENAFI_URL"
echo "Zone: $VENAFI_ZONE"
echo "Common Name: $CERT_CN"
echo "SANs: $CERT_SAN_DNS"
echo ""

# Build vcert command
VCERT_CMD="vcert enroll"
VCERT_CMD="$VCERT_CMD -u $VENAFI_URL"
VCERT_CMD="$VCERT_CMD --trust-bundle $VENAFI_CA_BUNDLE"
VCERT_CMD="$VCERT_CMD -z \"$VENAFI_ZONE\""
VCERT_CMD="$VCERT_CMD --cn \"$CERT_CN\""

# Add DNS SANs
IFS=',' read -ra SANS <<< "$CERT_SAN_DNS"
for san in "${SANS[@]}"; do
    VCERT_CMD="$VCERT_CMD --san-dns \"$san\""
done

# Output files
VCERT_CMD="$VCERT_CMD --key-file $OUTPUT_DIR/gateway-server.key"
VCERT_CMD="$VCERT_CMD --cert-file $OUTPUT_DIR/gateway-server.crt"
VCERT_CMD="$VCERT_CMD --chain-file $OUTPUT_DIR/gateway-server-chain.crt"

# Execute vcert command
echo "Requesting certificate..."
eval $VCERT_CMD

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Certificate successfully issued!"
    echo ""
    echo "Certificate files:"
    echo "  Private Key: $OUTPUT_DIR/gateway-server.key"
    echo "  Certificate: $OUTPUT_DIR/gateway-server.crt"
    echo "  Chain:       $OUTPUT_DIR/gateway-server-chain.crt"
    echo ""
    
    # Display certificate details
    echo "Certificate Details:"
    openssl x509 -in "$OUTPUT_DIR/gateway-server.crt" -noout -subject -issuer -dates -ext subjectAltName
    echo ""
    
    # Create Kubernetes secret YAML
    echo "Creating Kubernetes secret YAML..."
    cat > "$OUTPUT_DIR/gateway-tls-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: api-gateway-tls
  namespace: consul
type: kubernetes.io/tls
data:
  tls.crt: $(base64 < "$OUTPUT_DIR/gateway-server.crt" | tr -d '\n')
  tls.key: $(base64 < "$OUTPUT_DIR/gateway-server.key" | tr -d '\n')
EOF
    
    echo "✓ Kubernetes secret YAML created: $OUTPUT_DIR/gateway-tls-secret.yaml"
    echo ""
    
    # Create CA bundle ConfigMap YAML
    echo "Creating CA bundle ConfigMap YAML..."
    cat > "$OUTPUT_DIR/venafi-ca-bundle-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: venafi-ca-bundle
  namespace: consul
data:
  ca.crt: |
$(sed 's/^/    /' "$OUTPUT_DIR/gateway-server-chain.crt")
EOF
    
    echo "✓ CA bundle ConfigMap YAML created: $OUTPUT_DIR/venafi-ca-bundle-configmap.yaml"
    echo ""
    
    echo "Next steps:"
    echo "1. Apply the secret to Kubernetes:"
    echo "   kubectl apply -f $OUTPUT_DIR/gateway-tls-secret.yaml"
    echo ""
    echo "2. Apply the CA bundle ConfigMap:"
    echo "   kubectl apply -f $OUTPUT_DIR/venafi-ca-bundle-configmap.yaml"
    echo ""
    echo "3. Configure the API Gateway to use this certificate"
    
else
    echo ""
    echo "✗ Certificate request failed"
    exit 1
fi

# Made with Bob
