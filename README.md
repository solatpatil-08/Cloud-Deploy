# CloudDeploy – AWS-Based Containerized Application Deployment with CI/CD

CloudDeploy is an industry-grade deployment platform featuring a containerized Spring Boot 3 / Java 21 REST API deployed to AWS EC2 via an automated GitHub Actions CI/CD pipeline with zero-SSH (AWS Systems Manager) and observability integration.

---

## 🛠️ Technology Stack
* **Language & Runtime:** Java 21 LTS
* **Framework:** Spring Boot 3.4.2 (Jakarta EE 10 baseline)
* **Build Tool:** Maven
* **Database & Migrations:** PostgreSQL 16, Flyway
* **Security:** Spring Security 6, JWT Authentication (HMAC-SHA256 via JJWT 0.12), BCrypt
* **Reverse Proxy:** Nginx 1.27 (Rate limiting, security headers, SSL-ready)
* **Containerization:** Docker (Multi-stage build, non-root user), Docker Compose
* **Observability:** Spring Boot Actuator, Micrometer Prometheus, Structured JSON Logback
* **Cloud Infrastructure (Upcoming Phases):** AWS EC2, AWS ECR, AWS Systems Manager (SSM), AWS IAM (OIDC)
* **CI/CD (Upcoming Phases):** GitHub Actions with automated rollback

---

## 🚀 Phases Implemented

### Phase 1: Architecture & Technical Alignment
* Comprehensive system, component, and deployment architecture design.
* Zero-SSH security model utilizing AWS Systems Manager.
* Forward-compatible Spring Boot and Java 21 baseline.

### Phase 2: CloudDeploy Task Manager REST API
* Stateless JWT authentication (`/api/v1/auth/register`, `/api/v1/auth/login`).
* User-specific task ownership and isolation (`/api/v1/tasks`).
* Dynamic filtering (status, priority, search), pagination, and sorting.
* Flyway migrations with database indexes.

### Phase 3: Containerization & Compose Orchestration
* Production multi-stage `Dockerfile` (`maven:3.9-eclipse-temurin-21-alpine` $\to$ `eclipse-temurin:21-jre-alpine`).
* Hardened execution under unprivileged `appuser:appgroup`.
* `compose.yaml` (local dev) and `compose.prod.yaml` (ECR image deployment with data preservation).

### Phase 4: Nginx Reverse Proxy & Security Perimeter
* Front-facing reverse proxy exposing ports 80/443.
* Strict rate limiting (5 req/s on auth, 20 req/s on API).
* Public access to `/actuator/*` strictly blocked with HTTP 403 Forbidden.
* Internal health probe mapped to `/health`.
* Modern TLSv1.2 & TLSv1.3 configuration snippets ready for SSL certificate activation.

---

## 📡 API Endpoints

### Authentication
* `POST /api/v1/auth/register` - Create a new user account
* `POST /api/v1/auth/login` - Authenticate and retrieve JWT Bearer token

### Tasks (`Authorization: Bearer <token>`)
* `POST /api/v1/tasks` - Create a new task
* `GET /api/v1/tasks` - List user tasks (supports `status`, `priority`, `search`, `page`, `size`, `sortBy`, `sortDir`)
* `GET /api/v1/tasks/{id}` - Retrieve task details by ID
* `PUT /api/v1/tasks/{id}` - Update task details
* `PATCH /api/v1/tasks/{id}/status` - Update task status
* `DELETE /api/v1/tasks/{id}` - Delete task

### Monitoring & Gateway Probes
* `GET /health` - Public health probe through Nginx
* `GET /actuator/prometheus` - Prometheus scrape endpoint (internal network only)

---

## 💻 Local Quickstart with Docker Compose

```bash
# 1. Clone repository
git clone https://github.com/solatpatil-08/Cloud-Deploy.git
cd Cloud-Deploy

# 2. Setup environment variables
cp .env.example .env

# 3. Start containers
docker compose up -d

# 4. Run automated test suite
bash scripts/test-nginx-proxy.sh   # Linux/macOS
.\scripts\test-nginx-proxy.ps1      # Windows PowerShell
```
