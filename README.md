# CloudDeploy – AWS-Based Containerized Application Deployment with CI/CD

CloudDeploy is an industry-grade deployment platform featuring a containerized Spring Boot 3 / Java 21 REST API deployed to AWS EC2 via an automated GitHub Actions CI/CD pipeline with zero-SSH (AWS Systems Manager) and observability integration.

---

## 🛠️ Technology Stack
* **Language & Runtime:** Java 21 LTS
* **Framework:** Spring Boot 3.4.2 (Jakarta EE 10 baseline)
* **Build Tool:** Maven
* **Database & Migrations:** PostgreSQL 16, Flyway
* **Security:** Spring Security 6, JWT Authentication (HMAC-SHA256 via JJWT 0.12), BCrypt
* **Observability:** Spring Boot Actuator, Micrometer Prometheus, Structured JSON Logback (AWS CloudWatch)
* **Cloud Infrastructure (Upcoming Phases):** AWS EC2, AWS ECR, AWS Systems Manager (SSM), AWS IAM (OIDC)
* **Containerization & Web Server (Upcoming Phases):** Docker, Docker Compose, Nginx Reverse Proxy
* **CI/CD (Upcoming Phases):** GitHub Actions with automated rollback

---

## 🚀 Phase 2: CloudDeploy Task Manager API

### Features
1. **User Authentication:** Registration and login endpoints generating stateless HMAC-SHA256 JWT tokens.
2. **Task Management:** Full CRUD operations for user tasks with strict tenant isolation.
3. **Filtering, Pagination & Sorting:** Dynamic query parameters for task status (`TODO`, `IN_PROGRESS`, `COMPLETED`), priority (`LOW`, `MEDIUM`, `HIGH`), text search, and multi-field sorting.
4. **Database Migrations:** Version-controlled Flyway schema definitions and composite indexes.
5. **Observability:** Production metrics exposed at `/actuator/prometheus` and liveness/readiness at `/actuator/health`.

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

### Monitoring
* `GET /actuator/health` - Health probe
* `GET /actuator/prometheus` - Prometheus metrics scrape endpoint

---

## 💻 Local Development

### Prerequisites
* Java 21 JDK
* PostgreSQL 16 (or run with H2 test profile)
* Maven 3.9+

### Running the API
```bash
# Clone the repository
git clone https://github.com/solatpatil-08/Cloud-Deploy.git
cd Cloud-Deploy/backend

# Configure environment variables (optional, defaults provided in application.yml)
export DB_URL="jdbc:postgresql://localhost:5432/clouddeploy_db"
export DB_USERNAME="postgres"
export DB_PASSWORD="password"
export JWT_SECRET="your_256_bit_jwt_secret_key"

# Run Spring Boot application
mvn spring-boot:run
```

### Running Tests
```bash
mvn test
```
