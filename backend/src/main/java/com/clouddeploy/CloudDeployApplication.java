package com.clouddeploy;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.core.env.Environment;

@SpringBootApplication
public class CloudDeployApplication {

    private static final Logger log = LoggerFactory.getLogger(CloudDeployApplication.class);

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(CloudDeployApplication.class);
        Environment env = app.run(args).getEnvironment();

        String port = env.getProperty("server.port", "8080");
        String activeProfiles = String.join(", ", env.getActiveProfiles());

        log.info("""
                --------------------------------------------------------------------------------
                Application '{}' is running!
                Local:            http://localhost:{}
                Active Profiles:  [{}]
                Health Check:     http://localhost:{}/actuator/health
                Prometheus:       http://localhost:{}/actuator/prometheus
                --------------------------------------------------------------------------------
                """,
                env.getProperty("spring.application.name", "clouddeploy-task-manager"),
                port,
                activeProfiles.isEmpty() ? "default" : activeProfiles,
                port,
                port
        );
    }
}

