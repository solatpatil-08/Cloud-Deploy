# ==============================================================================
# Stage 1: Build & Package with Maven and JDK 21
# ==============================================================================
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder

WORKDIR /build

# Copy Maven POMs first to leverage Docker layer caching for dependencies
COPY pom.xml .

# Download dependencies offline (cached unless pom.xml changes)
RUN mvn dependency:go-offline -B

# Copy project source code
COPY src ./src

# Compile and package application without running tests (tests run in CI pipeline)
RUN mvn clean package -DskipTests -B

# ==============================================================================
# Stage 2: Minimal Production JRE Runtime
# ==============================================================================
FROM eclipse-temurin:21-jre-alpine AS runner

LABEL maintainer="CloudDeploy Team" \
      application="clouddeploy-task-manager" \
      version="1.0.0"

# Install curl for health checking and tzdata for accurate timezone management
RUN apk add --no-cache curl tzdata && \
    rm -rf /var/cache/apk/*

# Create dedicated non-root application user and group for security hardening
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -h /app

WORKDIR /app

# Copy compiled JAR from builder stage
COPY --from=builder /build/target/clouddeploy-task-manager-*.jar /app/app.jar

# Enforce ownership and strict permissions
RUN chown -R appuser:appgroup /app && \
    chmod 500 /app/app.jar

# Switch execution context to unprivileged user
USER appuser:appgroup

# Configure runtime environment variables
ENV PORT=8080 \
    SPRING_PROFILES_ACTIVE=prod \
    JAVA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

# Expose internal application port (not published to host directly)
EXPOSE 8080

# Configure container health probe against Spring Boot Actuator
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

# Launch the Spring Boot application using exec form
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]

