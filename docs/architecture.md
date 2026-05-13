# Architecture Overview: F5 to Consul API Gateway mTLS

## Purpose

This document explains the architecture at a high level for readers who want to quickly understand how traffic enters the platform, where mutual TLS is enforced, and how requests reach backend services.

Use this document if you are:

- new to the repository
- an application developer integrating with the platform
- reviewing the design at a conceptual level
- trying to understand the main trust boundaries without diving into platform implementation details

If you want the operator-focused deployment view, Kubernetes resource relationships, PKI details, and troubleshooting flow, see [architecture-diagram.md](./architecture-diagram.md).

## Executive Summary

This platform separates **public ingress**, **authenticated ingress**, and **internal service-to-service communication** into distinct layers:

- **External clients** connect to **F5** over standard HTTPS.
- **F5** connects to the **Consul API Gateway** over **mutual TLS (mTLS)**.
- **The API Gateway** forwards traffic to backend services through the **Consul service mesh**, which also uses **mTLS**.
- **Backend applications** do not terminate public TLS and do not manage ingress mutual-authentication directly.

This separation makes the architecture easier to secure and operate:

- **Public TLS** is handled at the edge.
- **Ingress mutual authentication** is enforced between **F5** and **API Gateway**.
- **Internal workload identity and encryption** are handled by **Consul Connect**.
- **Applications remain simple** and typically receive plain HTTP from a local sidecar.

## At a Glance

```mermaid
flowchart LR
    client([🌐 External Client])
    f5([🛡️ F5 Edge])
    gateway([🚪 Consul API Gateway])
    mesh([🔐 Consul Service Mesh])
    backend([📦 Backend Service])

    client -->|HTTPS| f5
    f5 -->|mTLS| gateway
    gateway -->|mTLS| mesh
    mesh -->|localhost HTTP| backend

    classDef blue fill:#e0f2fe,stroke:#0284c7,stroke-width:2px,color:#111827;
    classDef orange fill:#fff7ed,stroke:#ea580c,stroke-width:2px,color:#111827;
    classDef green fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#111827;
    classDef purple fill:#ede9fe,stroke:#7c3aed,stroke-width:2px,color:#111827;

    class client blue;
    class f5,gateway orange;
    class mesh green;
    class backend purple;
```

## The Main Components

### External Client

An external client can be:

- a browser
- a mobile app
- another API consumer
- an internal enterprise client coming from outside the cluster boundary

The client connects using **HTTPS** to the public endpoint exposed by F5.

### F5

F5 is the edge entry point for inbound traffic. It is responsible for:

- accepting public HTTPS traffic
- presenting the public-facing server certificate
- optionally applying edge controls such as inspection, WAF, or rate limiting
- acting as the **authenticated TLS client** when connecting onward to the API Gateway

In this architecture, F5 is not just a pass-through load balancer. It is also the component that establishes the next trust boundary toward the platform.

### Consul API Gateway

The Consul API Gateway is the Kubernetes-hosted ingress component inside the platform. It is responsible for:

- accepting traffic from F5
- presenting its server certificate for the ingress mTLS connection
- validating the client certificate presented by F5
- applying listener and routing rules
- forwarding the request into the service mesh

This is the main ingress control point inside the cluster.

### Consul Service Mesh

The Consul service mesh handles secure communication between platform workloads. It is responsible for:

- establishing mTLS between workloads
- issuing workload identities
- enforcing service-to-service authorization policies
- separating internal service security from edge ingress PKI

### Backend Service

The backend service is the destination application. In this design, the backend application:

- receives traffic through a mesh sidecar
- does not manage public ingress certificates
- does not directly terminate the F5-to-Gateway mTLS connection
- typically receives plain HTTP on localhost from the sidecar

## Why the Architecture Is Split into Layers

This architecture intentionally separates three concerns:

1. **Public ingress**
   - Client to F5
   - Standard HTTPS
   - Internet-facing certificate and edge controls

2. **Authenticated ingress to the platform**
   - F5 to API Gateway
   - Mutual TLS using Venafi-issued certificates
   - Primary ingress trust boundary

3. **Internal service-to-service security**
   - API Gateway to backend
   - Consul Connect mTLS
   - Workload identity and authorization inside the cluster

This separation keeps trust scopes smaller and operational responsibilities clearer.

## Trust Boundaries

| Boundary | Connection | TLS Mode | Trust Source | Why It Exists |
|---|---|---|---|---|
| 1 | External Client → F5 | HTTPS | Public CA | Protects public inbound traffic |
| 2 | F5 → API Gateway | mTLS | Venafi PKI | Authenticates ingress into the platform |
| 3 | API Gateway → Backend | mTLS | Consul CA | Secures internal workload communication |

> [!IMPORTANT]
> The most important trust boundary in this design is **F5 → API Gateway**. That is where ingress mutual authentication is enforced.

## Request Flow

A typical request follows this path:

1. A client connects to the public endpoint over **HTTPS**.
2. **F5** terminates the external TLS session and applies edge controls.
3. F5 opens a new **mTLS** connection to the **Consul API Gateway**.
4. The **API Gateway** validates F5's client certificate and applies routing rules.
5. The request is forwarded through the **Consul service mesh** using internal **mTLS**.
6. The backend sidecar forwards the request to the application, typically as **localhost HTTP**.
7. The response returns through the same layers in reverse.

## Why There Are Two PKI Domains

This architecture uses two different certificate domains on purpose.

### Public / Edge and Ingress PKI

Used for:

- public HTTPS at F5
- mTLS between F5 and API Gateway

This trust is managed separately because it belongs to the ingress boundary and usually follows enterprise PKI and certificate management processes.

### Service Mesh PKI

Used for:

- workload identity inside the cluster
- mTLS between sidecars and mesh-connected services

This trust is managed by Consul and is intentionally independent from edge ingress certificates.

### Why the separation matters

Keeping these PKI domains separate helps with:

- **security isolation**
- **different rotation models**
- **clear ownership boundaries**
- **simpler troubleshooting**

## What First-Time Readers Should Remember

If you remember only a few things, remember these:

- Clients connect to **F5**, not directly to the API Gateway.
- **F5 authenticates to the API Gateway using mTLS**.
- **Consul secures internal service-to-service traffic separately**.
- Backend applications stay simpler because they are not responsible for public TLS or ingress certificate validation.
- The design intentionally separates **edge security** from **internal mesh security**.

## When to Read the Deep-Dive Document

Read [architecture-diagram.md](./architecture-diagram.md) if you need to understand:

- which Kubernetes resources implement this architecture
- how `Gateway`, `HTTPRoute`, `ServiceIntentions`, and related resources fit together
- how certificates are stored and validated
- how to troubleshoot failures at each layer
- what operators should inspect when traffic is not flowing correctly
