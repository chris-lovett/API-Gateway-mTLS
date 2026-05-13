#!/bin/bash
#
# Request F5 Client Certificate from Venafi
#
# Usage: ./request-f5-client-cert.sh
#
# Environment Variables:
#   VENAFI_URL       - Venafi TPP URL (default: https://venafi.example.com/vedsdk)
#   VENAFI_ZONE      - Venafi policy zone (default: \VED\Policy\F5\Client-Certificates)
#   VENAFI_TOKEN     - Venafi access token (required)
#   CERT_CN          - Certificate common name (default: f5-load-balancer.example.com)
#   CERT_SAN_DNS     - Additional DNS SANs (comma-separated)
#   CERT_SAN_IP      - IP SANs (comma-separated)
#   OUTPUT_DIR       - Output directory for certificates (default: ./certs)
#

set -e

# Configuration
VENAFI_URL="${VENAFI_URL:-https://venafi.example.com/vedsdk}"
VENAFI_ZONE="${VENAFI_ZONE:-\\VED\\Policy\\F5\\Client-Certificates}"
CERT_CN="${CERT_CN:-f5-load-balancer.example.com}"
CERT_SAN_DNS="${CERT_SAN_DNS:-f5-lb-01.example.com,f5-lb-02.example.com}"
CERT_SAN_IP="${CERT_SAN_IP:-10.0.1.10,10.0.1.11}"
OUTPUT_DIR="${OUTPUT_DIR:-./certs}"
VENAFI_CA_BUNDLE="${VENAFI_CA_BUNDLE:-/etc/ssl/venafi-ca-bundle.pem}"

# Check required variables
if [ -z "$VENAFI_TOKEN" ]; then
    echo "Error: VENAFI_TOKEN environment variable is required"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "=== Requesting F5 Client Certificate from Venafi ==="
echo "Venafi URL: $VENAFI_URL"
echo "Zone: $VENAFI_ZONE"
echo "Common Name: $CERT_CN"
echo "DNS SANs: $CERT_SAN_DNS"
echo "IP SANs: $CERT_SAN_IP"
echo ""

# Build vcert command
VCERT_CMD="vcert enroll"
VCERT_CMD="$VCERT_CMD -u $VENAFI_URL"
VCERT_CMD="$VCERT_CMD --trust-bundle $VENAFI_CA_BUNDLE"
VCERT_CMD="$VCERT_CMD -z \"$VENAFI_ZONE\""
VCERT_CMD="$VCERT_CMD --cn \"$CERT_CN\""

# Add DNS SANs
if [ -n "$CERT_SAN_DNS" ]; then
    IFS=',' read -ra SANS <<< "$CERT_SAN_DNS"
    for san in "${SANS[@]}"; do
        VCERT_CMD="$VCERT_CMD --san-dns \"$san\""
    done
fi

# Add IP SANs
if [ -n "$CERT_SAN_IP" ]; then
    IFS=',' read -ra IPS <<< "$CERT_SAN_IP"
    for ip in "${IPS[@]}"; do
        VCERT_CMD="$VCERT_CMD --san-ip \"$ip\""
    done
fi

# Output files
VCERT_CMD="$VCERT_CMD --key-file $OUTPUT_DIR/f5-client.key"
VCERT_CMD="$VCERT_CMD --cert-file $OUTPUT_DIR/f5-client.crt"
VCERT_CMD="$VCERT_CMD --chain-file $OUTPUT_DIR/f5-client-chain.crt"

# Execute vcert command
echo "Requesting certificate..."
eval $VCERT_CMD

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Certificate successfully issued!"
    echo ""
    echo "Certificate files:"
    echo "  Private Key: $OUTPUT_DIR/f5-client.key"
    echo "  Certificate: $OUTPUT_DIR/f5-client.crt"
    echo "  Chain:       $OUTPUT_DIR/f5-client-chain.crt"
    echo ""
    
    # Display certificate details
    echo "Certificate Details:"
    openssl x509 -in "$OUTPUT_DIR/f5-client.crt" -noout -subject -issuer -dates -ext subjectAltName
    echo ""
    
    # Create combined PEM file for F5
    echo "Creating combined PEM file for F5..."
    cat "$OUTPUT_DIR/f5-client.crt" "$OUTPUT_DIR/f5-client-chain.crt" > "$OUTPUT_DIR/f5-client-fullchain.crt"
    echo "✓ Combined certificate created: $OUTPUT_DIR/f5-client-fullchain.crt"
    echo ""
    
    # Create F5 upload script
    cat > "$OUTPUT_DIR/upload-to-f5.sh" <<'EOF'
#!/bin/bash
#
# Upload F5 client certificate to F5 LTM
#
# Usage: F5_HOST=f5-lb-01.example.com F5_USER=admin F5_PASS=password ./upload-to-f5.sh
#

set -e

F5_HOST="${F5_HOST:-f5-lb-01.example.com}"
F5_USER="${F5_USER:-admin}"

if [ -z "$F5_PASS" ]; then
    echo "Error: F5_PASS environment variable is required"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Uploading certificates to F5 LTM ==="
echo "F5 Host: $F5_HOST"
echo ""

# Upload certificate
echo "Uploading certificate..."
curl -sk -u "$F5_USER:$F5_PASS" \
    -H "Content-Type: application/json" \
    -X POST "https://$F5_HOST/mgmt/shared/file-transfer/uploads/f5-client.crt" \
    --data-binary @"$SCRIPT_DIR/f5-client-fullchain.crt"

# Upload private key
echo "Uploading private key..."
curl -sk -u "$F5_USER:$F5_PASS" \
    -H "Content-Type: application/json" \
    -X POST "https://$F5_HOST/mgmt/shared/file-transfer/uploads/f5-client.key" \
    --data-binary @"$SCRIPT_DIR/f5-client.key"

# Install certificate
echo "Installing certificate..."
curl -sk -u "$F5_USER:$F5_PASS" \
    -H "Content-Type: application/json" \
    -X POST "https://$F5_HOST/mgmt/tm/sys/crypto/cert" \
    -d '{
        "command": "install",
        "name": "f5-client-cert",
        "from-local-file": "/var/config/rest/downloads/f5-client.crt"
    }'

# Install private key
echo "Installing private key..."
curl -sk -u "$F5_USER:$F5_PASS" \
    -H "Content-Type: application/json" \
    -X POST "https://$F5_HOST/mgmt/tm/sys/crypto/key" \
    -d '{
        "command": "install",
        "name": "f5-client-key",
        "from-local-file": "/var/config/rest/downloads/f5-client.key"
    }'

echo ""
echo "✓ Certificates uploaded and installed successfully!"
echo ""
echo "Next steps:"
echo "1. Configure SSL profile to use these certificates"
echo "2. Apply SSL profile to virtual server"
EOF
    
    chmod +x "$OUTPUT_DIR/upload-to-f5.sh"
    echo "✓ F5 upload script created: $OUTPUT_DIR/upload-to-f5.sh"
    echo ""
    
    echo "Next steps:"
    echo "1. Upload certificates to F5:"
    echo "   cd $OUTPUT_DIR"
    echo "   F5_HOST=f5-lb-01.example.com F5_USER=admin F5_PASS=password ./upload-to-f5.sh"
    echo ""
    echo "2. Or manually upload via F5 GUI:"
    echo "   - System > Certificate Management > Traffic Certificate Management > SSL Certificate List"
    echo "   - Import: $OUTPUT_DIR/f5-client-fullchain.crt"
    echo "   - Import: $OUTPUT_DIR/f5-client.key"
    echo ""
    echo "3. Configure F5 SSL profile to use the client certificate"
    
else
    echo ""
    echo "✗ Certificate request failed"
    exit 1
fi

# Made with Bob
