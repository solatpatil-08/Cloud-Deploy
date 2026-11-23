package com.clouddeploy.service;

import com.clouddeploy.dto.request.LoginRequest;
import com.clouddeploy.dto.request.RegisterRequest;
import com.clouddeploy.dto.response.AuthResponse;
import com.clouddeploy.exception.UserAlreadyExistsException;
import com.clouddeploy.model.Role;
import com.clouddeploy.model.User;
import com.clouddeploy.repository.UserRepository;
import com.clouddeploy.security.JwtTokenProvider;
import com.clouddeploy.security.UserPrincipal;
import com.clouddeploy.service.impl.AuthServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private AuthenticationManager authenticationManager;

    @Mock
    private JwtTokenProvider tokenProvider;

    @InjectMocks
    private AuthServiceImpl authService;

    private RegisterRequest registerRequest;
    private LoginRequest loginRequest;
    private User user;

    @BeforeEach
    void setUp() {
        registerRequest = new RegisterRequest("cloud_user", "cloud@example.com", "SecurePass123!");
        loginRequest = new LoginRequest("cloud_user", "SecurePass123!");

        user = new User("cloud_user", "cloud@example.com", "encodedPassword", Role.ROLE_USER);
        user.setId(10L);
    }

    @Test
    @DisplayName("Should register new user successfully")
    void testRegisterSuccess() {
        when(userRepository.existsByUsername(anyString())).thenReturn(false);
        when(userRepository.existsByEmail(anyString())).thenReturn(false);
        when(passwordEncoder.encode(anyString())).thenReturn("encodedPassword");
        when(userRepository.save(any(User.class))).thenReturn(user);
        when(tokenProvider.generateTokenFromUsername(anyString(), anyLong(), anyString())).thenReturn("mocked.jwt.token");

        AuthResponse response = authService.register(registerRequest);

        assertNotNull(response);
        assertEquals("cloud_user", response.getUsername());
        assertEquals("cloud@example.com", response.getEmail());
        assertEquals("mocked.jwt.token", response.getToken());
        assertEquals(Role.ROLE_USER, response.getRole());

        verify(userRepository, times(1)).save(any(User.class));
    }

    @Test
    @DisplayName("Should throw exception when registering with duplicate username")
    void testRegisterDuplicateUsername() {
        when(userRepository.existsByUsername("cloud_user")).thenReturn(true);

        assertThrows(UserAlreadyExistsException.class, () -> authService.register(registerRequest));
        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    @DisplayName("Should throw exception when registering with duplicate email")
    void testRegisterDuplicateEmail() {
        when(userRepository.existsByUsername("cloud_user")).thenReturn(false);
        when(userRepository.existsByEmail("cloud@example.com")).thenReturn(true);

        assertThrows(UserAlreadyExistsException.class, () -> authService.register(registerRequest));
        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    @DisplayName("Should authenticate user and return token on valid login")
    void testLoginSuccess() {
        UserPrincipal principal = new UserPrincipal(
                10L, "cloud_user", "cloud@example.com", "encodedPassword",
                Collections.singletonList(new SimpleGrantedAuthority("ROLE_USER"))
        );
        Authentication authentication = new UsernamePasswordAuthenticationToken(principal, null, principal.getAuthorities());

        when(authenticationManager.authenticate(any(UsernamePasswordAuthenticationToken.class))).thenReturn(authentication);
        when(tokenProvider.generateToken(authentication)).thenReturn("valid.login.jwt");

        AuthResponse response = authService.login(loginRequest);

        assertNotNull(response);
        assertEquals("valid.login.jwt", response.getToken());
        assertEquals("cloud_user", response.getUsername());
        assertEquals(10L, response.getId());
    }

    @Test
    @DisplayName("Should throw BadCredentialsException on invalid credentials")
    void testLoginInvalidCredentials() {
        when(authenticationManager.authenticate(any(UsernamePasswordAuthenticationToken.class)))
                .thenThrow(new BadCredentialsException("Bad credentials"));

        assertThrows(BadCredentialsException.class, () -> authService.login(loginRequest));
    }
}

