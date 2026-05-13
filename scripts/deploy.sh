#!/bin/bash
#
# Deploy Consul API Gateway with mTLS Configuration
#
# This script deploys the complete stack:
# 1. Venafi certificates
# 2. Kubernetes secrets and configmaps
# 3. Consul API Gateway
# 4. Backend services
# 5. Network policies
#
# Usage: ./deploy.sh [options]
#
# Options:
#   --namespace <name>    Namespace for API Gateway (default: consul)
#   --skip-certs          Skip certificate generation
#   --skip-f5             Skip F5 configuration
#   --dry-run             Show what would be deployed without applying
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="consul"
SKIP_CERTS=false
SKIP_F5=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --skip-certs)
            SKIP_CERTS=true
            shift
            ;;
        --skip-f5)
            SKIP_F5=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}=== Deploying Consul API Gateway with mTLS ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Repository: $REPO_ROOT"
echo ""

# Function to run kubectl with dry-run support
run_kubectl() {
    if [ "$DRY_RUN" = true ]; then
        kubectl "$@" --dry-run=client
    else
        kubectl "$@"
    fi
}

# Step 1: Create namespaces
echo -e "${YELLOW}Step 1: Creating namespaces${NC}"
run_kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
run_kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f - || true
echo -e "${GREEN}✓ Namespaces created${NC}"
echo ""

# Step 2: Generate certificates from Venafi
if [ "$SKIP_CERTS" = false ]; then
    echo -e "${YELLOW}Step 2: Generating certificates from Venafi${NC}"
    
    if [ -z "$VENAFI_TOKEN" ]; then
        echo -e "${RED}Error: VENAFI_TOKEN environment variable not set${NC}"
        echo "Please set VENAFI_TOKEN before running this script"
        exit 1
    fi
    
    # Generate API Gateway server certificate
    echo "Generating API Gateway server certificate..."
    cd "$REPO_ROOT/venafi/scripts"
    ./request-gateway-cert.sh
    
    # Generate F5 client certificate
    echo "Generating F5 client certificate..."
    ./request-f5-client-cert.sh
    
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✓ Certificates generated${NC}"
else
    echo -e "${YELLOW}Step 2: Skipping certificate generation${NC}"
fi
echo ""

# Step 3: Apply secrets and configmaps
echo -e "${YELLOW}Step 3: Applying secrets and configmaps${NC}"

# Apply API Gateway TLS secret
if [ -f "$REPO_ROOT/venafi/scripts/certs/gateway-tls-secret.yaml" ]; then
    echo "Applying API Gateway TLS secret..."
    run_kubectl apply -f "$REPO_ROOT/venafi/scripts/certs/gateway-tls-secret.yaml"
else
    echo -e "${RED}Warning: API Gateway TLS secret not found${NC}"
fi

# Apply Venafi CA bundle
if [ -f "$REPO_ROOT/venafi/scripts/certs/venafi-ca-bundle-configmap.yaml" ]; then
    echo "Applying Venafi CA bundle..."
    run_kubectl apply -f "$REPO_ROOT/venafi/scripts/certs/venafi-ca-bundle-configmap.yaml"
else
    echo -e "${RED}Warning: Venafi CA bundle not found${NC}"
fi

echo -e "${GREEN}✓ Secrets and configmaps applied${NC}"
echo ""

# Step 4: Deploy Consul API Gateway
echo -e "${YELLOW}Step 4: Deploying Consul API Gateway${NC}"

# Apply GatewayClass
echo "Applying GatewayClass..."
run_kubectl apply -f "$REPO_ROOT/consul-gateway/gateway-class.yaml"

# Apply Gateway
echo "Applying Gateway..."
run_kubectl apply -f "$REPO_ROOT/consul-gateway/gateway.yaml"

# Wait for Gateway to be ready
if [ "$DRY_RUN" = false ]; then
    echo "Waiting for Gateway to be ready..."
    kubectl wait --for=condition=Programmed gateway/api-gateway -n "$NAMESPACE" --timeout=300s || true
fi

echo -e "${GREEN}✓ Consul API Gateway deployed${NC}"
echo ""

# Step 5: Deploy HTTPRoutes
echo -e "${YELLOW}Step 5: Deploying HTTPRoutes${NC}"
run_kubectl apply -f "$REPO_ROOT/consul-gateway/routes/"
echo -e "${GREEN}✓ HTTPRoutes deployed${NC}"
echo ""

# Step 6: Deploy Service Intentions
echo -e "${YELLOW}Step 6: Deploying Service Intentions${NC}"
run_kubectl apply -f "$REPO_ROOT/consul-gateway/intentions/"
echo -e "${GREEN}✓ Service Intentions deployed${NC}"
echo ""

# Step 7: Deploy Network Policies
echo -e "${YELLOW}Step 7: Deploying Network Policies${NC}"
run_kubectl apply -f "$REPO_ROOT/kubernetes/network-policies/"
echo -e "${GREEN}✓ Network Policies deployed${NC}"
echo ""

# Step 8: Deploy Backend Services
echo -e "${YELLOW}Step 8: Deploying Backend Services${NC}"
run_kubectl apply -f "$REPO_ROOT/kubernetes/deployments/"
echo -e "${GREEN}✓ Backend Services deployed${NC}"
echo ""

# Step 9: Configure F5 (if not skipped)
if [ "$SKIP_F5" = false ]; then
    echo -e "${YELLOW}Step 9: Configuring F5 LTM${NC}"
    echo "F5 configuration must be done manually or via F5 automation tools"
    echo ""
    echo "Steps:"
    echo "1. Upload F5 client certificate:"
    echo "   cd $REPO_ROOT/venafi/scripts/certs"
    echo "   F5_HOST=<f5-host> F5_USER=admin F5_PASS=<password> ./upload-to-f5.sh"
    echo ""
    echo "2. Apply F5 configuration:"
    echo "   tmsh -f $REPO_ROOT/f5/ssl-profiles/server-ssl-profile.tmsh"
    echo "   tmsh -f $REPO_ROOT/f5/ssl-profiles/client-ssl-profile.tmsh"
    echo "   tmsh -f $REPO_ROOT/f5/pools/api-gateway-pool.tmsh"
    echo "   tmsh -f $REPO_ROOT/f5/virtual-servers/api-gateway-vs.tmsh"
    echo ""
else
    echo -e "${YELLOW}Step 9: Skipping F5 configuration${NC}"
fi
echo ""

# Step 10: Verify deployment
echo -e "${YELLOW}Step 10: Verifying deployment${NC}"

if [ "$DRY_RUN" = false ]; then
    echo "Checking Gateway status..."
    kubectl get gateway -n "$NAMESPACE"
    echo ""
    
    echo "Checking HTTPRoutes..."
    kubectl get httproute -A
    echo ""
    
    echo "Checking Service Intentions..."
    kubectl get serviceintentions -A
    echo ""
    
    echo "Checking Backend Services..."
    kubectl get pods -n default -l app=backend
    echo ""
    
    echo "Checking API Gateway Service..."
    kubectl get svc -n "$NAMESPACE" api-gateway
    echo ""
fi

echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Verify Gateway is accessible from F5:"
echo "   kubectl get svc -n $NAMESPACE api-gateway"
echo ""
echo "2. Test mTLS connection from F5:"
echo "   openssl s_client -connect <gateway-ip>:443 -cert f5-client.crt -key f5-client.key"
echo ""
echo "3. Monitor Gateway logs:"
echo "   kubectl logs -n $NAMESPACE -l app=api-gateway -f"
echo ""
echo "4. Check metrics:"
echo "   kubectl port-forward -n $NAMESPACE svc/api-gateway 9090:9090"
echo "   curl http://localhost:9090/metrics"

# Made with Bob
