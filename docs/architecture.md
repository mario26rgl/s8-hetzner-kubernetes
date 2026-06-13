# Architecture Diagrams (C1 → C4)

> Generated from source code. Mail-service excluded (deprecated).

---

## C1 — System Context

```mermaid
flowchart TD
    User(["👤 End User"])

    subgraph S8 ["S8 Platform — Hetzner K3s"]
        Platform["Microservices"]
    end

    PG[("PostgreSQL")]
    MG[("MongoDB")]
    RMQ[["RabbitMQ"]]
    OBS["Prometheus / Grafana"]

    User -->|HTTPS| S8
    S8 -->|TCP 5432| PG
    S8 -->|TCP 27017| MG
    S8 -->|AMQP 5672| RMQ
    S8 -->|HTTP /metrics scrape| OBS
```

---

## C2 — Container Diagram

```mermaid
flowchart TD
    User(["👤 End User"])

    subgraph Ingress ["Traefik Ingress"]
        FE["**front-end**\nGo · HTTP :80\nServes UI, reverse-proxies /api/*"]
    end

    subgraph Core ["Core Services"]
        direction LR
        Broker["**broker-service**\nGo · HTTP :80\nAPI gateway — routes actions"]
        Auth["**auth-service**\nGo · HTTP :80\nAuthenticate / SignUp / Verify"]
        Logger["**logger-service**\nGo · HTTP :80 · RPC :5001 · gRPC :50051\nPersists log entries"]
        Listener["**listener-service**\nGo · AMQP consumer\nForwards events to logger via RPC"]
    end

    PG[("PostgreSQL\nusers DB")]
    MG[("MongoDB\nlogs DB")]
    RMQ[["RabbitMQ\nlogs_topic"]]

    User -->|HTTPS| FE
    FE -->|"HTTP reverse-proxy /api/*"| Broker
    Broker -->|"HTTP POST /authenticate\n/signup  /verify"| Auth
    Broker -->|"AMQP publish\naction=log"| RMQ
    Broker -->|"gRPC WriteLog\n:50051"| Logger
    Auth -->|"HTTP POST /log\n(audit events)"| Logger
    RMQ -->|"AMQP consume\nlog.INFO/WARNING/ERROR"| Listener
    Listener -->|"TCP RPC :5001\nRPCServer.LogInfo"| Logger
    Auth -->|SQL pgx| PG
    Logger -->|MongoDB driver| MG
```

---

## C3 — broker-service internals

```mermaid
flowchart LR
    subgraph Broker ["broker-service"]
        direction TB
        Router["Chi Router\nCORS · Prometheus middleware"]
        HS["HandleSubmission\nswitch on action"]
        AH["authenticate /\nsignUp / verifyToken"]
        LR["logEventViaRabbit\n→ pushToQueue"]
        LG["logItemViaGRPC"]
        EM["EventEmitter\nevent/emit.go"]

        Router -->|"POST /handle"| HS
        Router -->|"POST /log-grpc"| LG
        HS -->|"action=auth\nsignup\nverify"| AH
        HS -->|"action=log"| LR
        LR --> EM
    end

    AUTH["auth-service\nHTTP"]
    RMQ[["RabbitMQ\nAMQP"]]
    LOG["logger-service\ngRPC :50051"]

    AH -->|HTTP POST| AUTH
    EM -->|AMQP publish| RMQ
    LG -->|gRPC WriteLog| LOG
```

---

## C3 — auth-service internals

```mermaid
flowchart LR
    subgraph Auth ["auth-service"]
        direction TB
        Router["Chi Router"]
        Authenticate["Authenticate\nvalidate creds → issue token"]
        SignUp["SignUp\ncreate user → issue token"]
        Verify["Verify\nvalidate HMAC token"]
        TokenUtil["Token Utils\ngenerateAuthToken\nverifyAuthToken\n(HMAC-SHA256 + base64)"]
        Model["User Model\ndata/models.go\nGetByEmail · GetOne · Insert"]
        LogReq["logRequest\nfire-and-forget"]

        Router -->|"POST /authenticate"| Authenticate
        Router -->|"POST /signup"| SignUp
        Router -->|"POST /verify"| Verify
        Authenticate --> TokenUtil
        Authenticate --> Model
        Authenticate --> LogReq
        SignUp --> TokenUtil
        SignUp --> Model
        SignUp --> LogReq
        Verify --> TokenUtil
        Verify --> Model
    end

    PG[("PostgreSQL")]
    LOG["logger-service\nHTTP /log"]

    Model -->|pgx SQL| PG
    LogReq -->|HTTP POST| LOG
```

---

## C3 — logger-service internals

```mermaid
flowchart LR
    subgraph Logger ["logger-service"]
        direction TB
        HTTP["HTTP Server\nPOST /log\n:80"]
        RPC["RPC Server\nRPCServer.LogInfo\n:5001"]
        GRPC["gRPC Server\nLogService.WriteLog\n:50051"]
        Model["LogEntry Model\ndata/models.go\nInsert"]

        HTTP --> Model
        RPC -->|direct InsertOne| Model
        GRPC --> Model
    end

    MG[("MongoDB\nlogs collection")]
    Model -->|MongoDB driver| MG
```

---

## C3 — listener-service internals

```mermaid
flowchart LR
    subgraph Listener ["listener-service"]
        direction TB
        Main["main.go\nconnect → start Consumer"]
        Consumer["Consumer\nevent/consumer.go\nbind logs_topic exchange"]
        Handler["handlePayload\ndispatch on payload.Name"]
        RPC["logEventViaRPC\nrpc.Dial :5001"]
        Metrics["Prometheus\nHTTP :2112/metrics"]

        Main --> Consumer
        Main --> Metrics
        Consumer -->|per message| Handler
        Handler -->|"name=log\nor event"| RPC
    end

    RMQ[["RabbitMQ\nlog.INFO/WARNING/ERROR"]]
    LOG["logger-service\nRPC :5001"]

    RMQ -->|AMQP consume| Consumer
    RPC -->|RPCServer.LogInfo| LOG
```

---

## C4 — Request flow: `action=log` (async path)

```mermaid
sequenceDiagram
    actor User
    participant FE   as front-end
    participant Bkr  as broker-service
    participant RMQ  as RabbitMQ
    participant Lst  as listener-service
    participant Log  as logger-service
    participant MG   as MongoDB

    User->>FE: POST /api/handle<br/>{action:"log", log:{...}}
    FE->>Bkr: HTTP POST /handle (proxied)

    Bkr->>RMQ: AMQP publish → logs_topic [routing_key=INFO]
    Bkr-->>FE: 202 Accepted
    FE-->>User: 202 "Logged via RabbitMQ!"

    RMQ->>Lst: deliver message
    Lst->>Lst: json.Unmarshal → Payload
    Lst->>Log: TCP RPC — RPCServer.LogInfo
    Log->>MG: collection.InsertOne(LogEntry)
    MG-->>Log: ok
    Log-->>Lst: "Log entry created successfully"
```
