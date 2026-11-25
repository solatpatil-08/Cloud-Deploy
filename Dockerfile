# ==============================================================================
# CloudDeploy - Root Multi-Stage Dockerfile (Builds from repo root)
# ==============================================================================

# Stage 1: Build with Maven 3.9 and Java 21
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder

WORKDIR /build

# Copy Maven POMs first for dependency layer caching
COPY pom.xml .
COPY backend/pom.xml ./backend/

# Resolve dependencies
RUN mvn dependency:go-offline -B -f backend/pom.xml || true

# Copy source code
COPY backend/src ./backend/src

# Compile and package application (skip tests as they run in CI)
RUN mvn clean package -DskipTests -B -f backend/pom.xml

# Stage 2: Minimal Production JRE Runtime
FROM eclipse-temurin:21-jre-alpine AS runner

LABEL maintainer="CloudDeploy Team" \
      application="clouddeploy-task-manager" \
      version="1.0.0"

RUN apk add --no-cache curl tzdata && \
    rm -rf /var/cache/apk/*

RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -h /app

WORKDIR /app

COPY --from=builder /build/backend/target/clouddeploy-task-manager-*.jar /app/app.jar

RUN chown -R appuser:appgroup /app && \
    chmod 500 /app/app.jar

USER appuser:appgroup

ENV PORT=8080 \
    SPRING_PROFILES_ACTIVE=prod \
    JAVA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
