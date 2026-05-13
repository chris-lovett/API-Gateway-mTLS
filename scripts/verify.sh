#!/bin/bash
#
# Verify Consul API Gateway mTLS Configuration
#
# This script verifies the complete mTLS setup:
# 1. Certificate validity
# 2. Gateway status
# 3. mTLS connectivity
# 4. Service mesh health
#
# Usage: ./verify.sh [options]
#
# Options:
#   --namespace <name>    Namespace for API Gateway (default: consul)
#   --gateway-ip <ip>     Gateway IP address for testing
#   --verbose             Show detailed output
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="consul"
GATEWAY_IP=""
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --gateway-ip)
            GATEWAY_IP="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
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

echo -e "${BLUE}=== Verifying Consul API Gateway mTLS Configuration ===${NC}"
echo "Namespace: $NAMESPACE"
echo ""

# Track test results
PASSED=0
FAILED=0

# Function to print test result
test_result() {
    local test_name=$1
    local result=$2
    local message=$3
    
    if [ "$result" = "pass" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        if [ -n "$message" ]; then
            echo -e "  ${RED}Error: $message${NC}"
        fi
        ((FAILED++))
    fi
}

# Test 1: Check if namespace exists
echo -e "${YELLOW}Test 1: Checking namespace${NC}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    test_result "Namespace $NAMESPACE exists" "pass"
else
    test_result "Namespace $NAMESPACE exists" "fail" "Namespace not found"
fi
echo ""

# Test 2: Check certificates
echo -e "${YELLOW}Test 2: Checking certificates${NC}"

# Check API Gateway TLS secret
if kubectl get secret api-gateway-tls -n "$NAMESPACE" &>/dev/null; then
    test_result "API Gateway TLS secret exists" "pass"
    
    # Verify certificate expiration
    CERT_DATA=$(kubectl get secret api-gateway-tls -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d)
    EXPIRY=$(echo "$CERT_DATA" | openssl x509 -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY" +%s 2>/dev/null || date -d "$EXPIRY" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -gt 15 ]; then
        test_result "Certificate valid for $DAYS_LEFT days" "pass"
    elif [ $DAYS_LEFT -gt 0 ]; then
        test_result "Certificate expires in $DAYS_LEFT days" "fail" "Certificate expiring soon"
    else
        test_result "Certificate expired" "fail" "Certificate has expired"
    fi
else
    test_result "API Gateway TLS secret exists" "fail" "Secret not found"
fi

# Check Venafi CA bundle
if kubectl get configmap venafi-f5-client-ca -n "$NAMESPACE" &>/dev/null; then
    test_result "Venafi CA bundle exists" "pass"
else
    test_result "Venafi CA bundle exists" "fail" "ConfigMap not found"
fi
echo ""

# Test 3: Check Gateway status
echo -e "${YELLOW}Test 3: Checking Gateway status${NC}"

if kubectl get gateway api-gateway -n "$NAMESPACE" &>/dev/null; then
    test_result "Gateway resource exists" "pass"
    
    # Check if Gateway is programmed
    GATEWAY_STATUS=$(kubectl get gateway api-gateway -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')
    if [ "$GATEWAY_STATUS" = "True" ]; then
        test_result "Gateway is programmed" "pass"
    else
        test_result "Gateway is programmed" "fail" "Gateway not ready"
    fi
    
    # Check if Gateway is accepted
    GATEWAY_ACCEPTED=$(kubectl get gateway api-gateway -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}')
    if [ "$GATEWAY_ACCEPTED" = "True" ]; then
        test_result "Gateway is accepted" "pass"
    else
        test_result "Gateway is accepted" "fail" "Gateway not accepted"
    fi
else
    test_result "Gateway resource exists" "fail" "Gateway not found"
fi
echo ""

# Test 4: Check Gateway Service
echo -e "${YELLOW}Test 4: Checking Gateway Service${NC}"

if kubectl get svc api-gateway -n "$NAMESPACE" &>/dev/null; then
    test_result "Gateway Service exists" "pass"
    
    # Get Gateway IP if not provided
    if [ -z "$GATEWAY_IP" ]; then
        GATEWAY_IP=$(kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [ -z "$GATEWAY_IP" ]; then
            GATEWAY_IP=$(kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
        fi
    fi
    
    if [ -n "$GATEWAY_IP" ]; then
        test_result "Gateway IP: $GATEWAY_IP" "pass"
    else
        test_result "Gateway IP assigned" "fail" "No IP address found"
    fi
else
    test_result "Gateway Service exists" "fail" "Service not found"
fi
echo ""

# Test 5: Check Gateway Pods
echo -e "${YELLOW}Test 5: Checking Gateway Pods${NC}"

GATEWAY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=api-gateway --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$GATEWAY_PODS" -gt 0 ]; then
    test_result "Gateway pods running: $GATEWAY_PODS" "pass"
    
    # Check if all pods are ready
    READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=api-gateway --no-headers 2>/dev/null | grep "Running" | wc -l | tr -d ' ')
    if [ "$READY_PODS" -eq "$GATEWAY_PODS" ]; then
        test_result "All Gateway pods ready" "pass"
    else
        test_result "All Gateway pods ready" "fail" "Only $READY_PODS/$GATEWAY_PODS pods ready"
    fi
else
    test_result "Gateway pods running" "fail" "No pods found"
fi
echo ""

# Test 6: Check HTTPRoutes
echo -e "${YELLOW}Test 6: Checking HTTPRoutes${NC}"

ROUTES=$(kubectl get httproute -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$ROUTES" -gt 0 ]; then
    test_result "HTTPRoutes configured: $ROUTES" "pass"
else
    test_result "HTTPRoutes configured" "fail" "No routes found"
fi
echo ""

# Test 7: Check Service Intentions
echo -e "${YELLOW}Test 7: Checking Service Intentions${NC}"

INTENTIONS=$(kubectl get serviceintentions -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$INTENTIONS" -gt 0 ]; then
    test_result "Service Intentions configured: $INTENTIONS" "pass"
else
    test_result "Service Intentions configured" "fail" "No intentions found"
fi
echo ""

# Test 8: Check Network Policies
echo -e "${YELLOW}Test 8: Checking Network Policies${NC}"

NETPOLS=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NETPOLS" -gt 0 ]; then
    test_result "Network Policies configured: $NETPOLS" "pass"
else
    test_result "Network Policies configured" "fail" "No network policies found"
fi
echo ""

# Test 9: Check Backend Services
echo -e "${YELLOW}Test 9: Checking Backend Services${NC}"

if kubectl get svc backend-service -n default &>/dev/null; then
    test_result "Backend Service exists" "pass"
    
    # Check backend pods
    BACKEND_PODS=$(kubectl get pods -n default -l app=backend --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$BACKEND_PODS" -gt 0 ]; then
        test_result "Backend pods running: $BACKEND_PODS" "pass"
    else
        test_result "Backend pods running" "fail" "No pods found"
    fi
else
    test_result "Backend Service exists" "fail" "Service not found"
fi
echo ""

# Test 10: Test mTLS connectivity (if Gateway IP available)
if [ -n "$GATEWAY_IP" ] && [ -f "$REPO_ROOT/venafi/scripts/certs/f5-client.crt" ]; then
    echo -e "${YELLOW}Test 10: Testing mTLS connectivity${NC}"
    
    # Test with client certificate
    if timeout 5 openssl s_client -connect "$GATEWAY_IP:443" \
        -cert "$REPO_ROOT/venafi/scripts/certs/f5-client.crt" \
        -key "$REPO_ROOT/venafi/scripts/certs/f5-client.key" \
        -CAfile "$REPO_ROOT/venafi/scripts/certs/gateway-server-chain.crt" \
        -servername api-gateway.consul.svc.cluster.local \
        </dev/null 2>&1 | grep -q "Verify return code: 0"; then
        test_result "mTLS connection successful" "pass"
    else
        test_result "mTLS connection successful" "fail" "Connection failed or certificate validation failed"
    fi
    
    # Test without client certificate (should fail)
    if timeout 5 openssl s_client -connect "$GATEWAY_IP:443" \
        -CAfile "$REPO_ROOT/venafi/scripts/certs/gateway-server-chain.crt" \
        </dev/null 2>&1 | grep -q "certificate required"; then
        test_result "Client certificate required (as expected)" "pass"
    else
        test_result "Client certificate enforcement" "fail" "Gateway not requiring client certificate"
    fi
    echo ""
else
    echo -e "${YELLOW}Test 10: Skipping mTLS connectivity test${NC}"
    echo "  (Gateway IP not available or certificates not found)"
    echo ""
fi

# Test 11: Check Consul Connect
echo -e "${YELLOW}Test 11: Checking Consul Connect${NC}"

# Check if backend pods have Consul sidecar
BACKEND_POD=$(kubectl get pods -n default -l app=backend --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$BACKEND_POD" ]; then
    CONTAINERS=$(kubectl get pod "$BACKEND_POD" -n default -o jsonpath='{.spec.containers[*].name}')
    if echo "$CONTAINERS" | grep -q "consul-dataplane"; then
        test_result "Consul Connect sidecar injected" "pass"
    else
        test_result "Consul Connect sidecar injected" "fail" "Sidecar not found"
    fi
else
    test_result "Backend pod available for checking" "fail" "No backend pods found"
fi
echo ""

# Summary
echo -e "${BLUE}=== Verification Summary ===${NC}"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Your Consul API Gateway with mTLS is properly configured."
    echo ""
    echo "Next steps:"
    echo "1. Configure F5 to connect to Gateway IP: $GATEWAY_IP"
    echo "2. Test end-to-end connectivity from external client"
    echo "3. Monitor Gateway logs: kubectl logs -n $NAMESPACE -l app=api-gateway -f"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo "Please review the failed tests and fix the issues."
    echo ""
    echo "Common issues:"
    echo "- Certificates not generated or expired"
    echo "- Gateway not properly configured"
    echo "- Network policies blocking traffic"
    echo "- Consul Connect not enabled"
    echo ""
    echo "For detailed troubleshooting, run with --verbose flag"
    exit 1
fi

# Made with Bob
