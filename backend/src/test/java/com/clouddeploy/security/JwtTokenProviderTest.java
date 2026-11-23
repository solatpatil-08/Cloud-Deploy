package com.clouddeploy.security;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;

class JwtTokenProviderTest {

    private JwtTokenProvider jwtTokenProvider;
    private final String secret = "404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970";
    private final long expirationMs = 3600000; // 1 hour

    @BeforeEach
    void setUp() {
        jwtTokenProvider = new JwtTokenProvider(secret, expirationMs);
    }

    @Test
    @DisplayName("Should generate valid JWT token from Authentication")
    void testGenerateTokenFromAuthentication() {
        UserPrincipal userPrincipal = new UserPrincipal(
                1L, "devops_user", "devops@example.com", "password",
                Collections.singletonList(new SimpleGrantedAuthority("ROLE_USER"))
        );
        Authentication authentication = new UsernamePasswordAuthenticationToken(userPrincipal, null, userPrincipal.getAuthorities());

        String token = jwtTokenProvider.generateToken(authentication);

        assertNotNull(token);
        assertTrue(jwtTokenProvider.validateToken(token));
        assertEquals("devops_user", jwtTokenProvider.getUsernameFromJwt(token));
        assertEquals(1L, jwtTokenProvider.getUserIdFromJwt(token));
    }

    @Test
    @DisplayName("Should generate valid JWT token from direct parameters")
    void testGenerateTokenFromParams() {
        String token = jwtTokenProvider.generateTokenFromUsername("admin_user", 2L, "admin@example.com");

        assertNotNull(token);
        assertTrue(jwtTokenProvider.validateToken(token));
        assertEquals("admin_user", jwtTokenProvider.getUsernameFromJwt(token));
        assertEquals(2L, jwtTokenProvider.getUserIdFromJwt(token));
    }

    @Test
    @DisplayName("Should reject invalid or malformed JWT token")
    void testValidateTokenWithMalformedString() {
        String invalidToken = "not.a.valid.jwt.token";

        boolean isValid = jwtTokenProvider.validateToken(invalidToken);

        assertFalse(isValid);
    }

    @Test
    @DisplayName("Should reject expired token")
    void testValidateExpiredToken() {
        // Create provider with 1ms expiration
        JwtTokenProvider shortLivedProvider = new JwtTokenProvider(secret, 1);
        String token = shortLivedProvider.generateTokenFromUsername("expired_user", 3L, "expired@example.com");

        try {
            Thread.sleep(15);
        } catch (InterruptedException ignored) {}

        boolean isValid = shortLivedProvider.validateToken(token);
        assertFalse(isValid);
    }
}

