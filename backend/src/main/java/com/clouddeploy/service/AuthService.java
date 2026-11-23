package com.clouddeploy.service;

import com.clouddeploy.dto.request.LoginRequest;
import com.clouddeploy.dto.request.RegisterRequest;
import com.clouddeploy.dto.response.AuthResponse;

public interface AuthService {

    AuthResponse register(RegisterRequest registerRequest);

    AuthResponse login(LoginRequest loginRequest);
}

