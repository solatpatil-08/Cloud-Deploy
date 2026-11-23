package com.clouddeploy.service.impl;

import com.clouddeploy.dto.request.LoginRequest;
import com.clouddeploy.dto.request.RegisterRequest;
import com.clouddeploy.dto.response.AuthResponse;
import com.clouddeploy.exception.UserAlreadyExistsException;
import com.clouddeploy.model.Role;
import com.clouddeploy.model.User;
import com.clouddeploy.repository.UserRepository;
import com.clouddeploy.security.JwtTokenProvider;
import com.clouddeploy.security.UserPrincipal;
import com.clouddeploy.service.AuthService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthServiceImpl implements AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthServiceImpl.class);

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final AuthenticationManager authenticationManager;
    private final JwtTokenProvider tokenProvider;

    public AuthServiceImpl(UserRepository userRepository,
                           PasswordEncoder passwordEncoder,
                           AuthenticationManager authenticationManager,
                           JwtTokenProvider tokenProvider) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.authenticationManager = authenticationManager;
        this.tokenProvider = tokenProvider;
    }

    @Override
    @Transactional
    public AuthResponse register(RegisterRequest registerRequest) {
        log.info("Attempting registration for username: {}", registerRequest.getUsername());

        if (userRepository.existsByUsername(registerRequest.getUsername())) {
            throw new UserAlreadyExistsException("Username is already taken: " + registerRequest.getUsername());
        }

        if (userRepository.existsByEmail(registerRequest.getEmail())) {
            throw new UserAlreadyExistsException("Email is already in use: " + registerRequest.getEmail());
        }

        User user = new User(
                registerRequest.getUsername(),
                registerRequest.getEmail(),
                passwordEncoder.encode(registerRequest.getPassword()),
                Role.ROLE_USER
        );

        User savedUser = userRepository.save(user);
        log.info("Successfully registered user with id: {}", savedUser.getId());

        String jwt = tokenProvider.generateTokenFromUsername(
                savedUser.getUsername(),
                savedUser.getId(),
                savedUser.getEmail()
        );

        return new AuthResponse(jwt, savedUser.getId(), savedUser.getUsername(), savedUser.getEmail(), savedUser.getRole());
    }

    @Override
    public AuthResponse login(LoginRequest loginRequest) {
        log.info("Attempting login for user: {}", loginRequest.getUsernameOrEmail());

        Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                        loginRequest.getUsernameOrEmail(),
                        loginRequest.getPassword()
                )
        );

        SecurityContextHolder.getContext().setAuthentication(authentication);
        UserPrincipal userPrincipal = (UserPrincipal) authentication.getPrincipal();

        String jwt = tokenProvider.generateToken(authentication);
        log.info("Successfully authenticated user: {}", userPrincipal.getUsername());

        Role role = userPrincipal.getAuthorities().stream()
                .findFirst()
                .map(a -> Role.valueOf(a.getAuthority()))
                .orElse(Role.ROLE_USER);

        return new AuthResponse(jwt, userPrincipal.getId(), userPrincipal.getUsername(), userPrincipal.getEmail(), role);
    }
}

