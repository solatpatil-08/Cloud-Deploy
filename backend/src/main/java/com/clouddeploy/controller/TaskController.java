package com.clouddeploy.controller;

import com.clouddeploy.dto.request.CreateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskStatusRequest;
import com.clouddeploy.dto.response.ApiResponse;
import com.clouddeploy.dto.response.PagedResponse;
import com.clouddeploy.dto.response.TaskResponse;
import com.clouddeploy.model.TaskPriority;
import com.clouddeploy.model.TaskStatus;
import com.clouddeploy.security.UserPrincipal;
import com.clouddeploy.service.TaskService;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/tasks")
public class TaskController {

    private static final Logger log = LoggerFactory.getLogger(TaskController.class);
    private final TaskService taskService;

    public TaskController(TaskService taskService) {
        this.taskService = taskService;
    }

    @PostMapping
    public ResponseEntity<TaskResponse> createTask(
            @Valid @RequestBody CreateTaskRequest request,
            @AuthenticationPrincipal UserPrincipal currentUser) {
        log.info("Create task request received from user: {}", currentUser.getUsername());
        TaskResponse response = taskService.createTask(request, currentUser.getId());
        return new ResponseEntity<>(response, HttpStatus.CREATED);
    }

    @GetMapping
    public ResponseEntity<PagedResponse<TaskResponse>> getTasks(
            @RequestParam(required = false) TaskStatus status,
            @RequestParam(required = false) TaskPriority priority,
            @RequestParam(required = false) String search,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "createdAt") String sortBy,
            @RequestParam(defaultValue = "desc") String sortDir,
            @AuthenticationPrincipal UserPrincipal currentUser) {
        log.debug("Get tasks list request received from user: {}", currentUser.getUsername());
        PagedResponse<TaskResponse> response = taskService.getTasks(
                currentUser.getId(), status, priority, search, page, size, sortBy, sortDir);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<TaskResponse> getTaskById(
            @PathVariable Long id,
            @AuthenticationPrincipal UserPrincipal currentUser) {
        log.debug("Get task by id {} requested by user: {}", id, currentUser.getUsername());
        TaskResponse response = taskService.getTaskById(id, currentUser.getId());
        return ResponseEntity.ok(response);
    }

    @PutMapping("/{id}")
    public ResponseEntity<TaskResponse> updateTask(
            @PathVariable Long id,
            @Valid @RequestBody UpdateTaskRequest request,
            @AuthenticationPrincipal UserPrincipal currentUser) {
        log.info("Update task {} requested by user: {}", id, currentUser.getUsername());
        TaskResponse response = taskService.updateTask(id, request, currentUser.getId());
        return ResponseEntity.ok(response);
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<TaskResponse> updateTaskStatus(
            @PathVariable Long id,
            @Valid @RequestBody UpdateTaskStatusRequest request,
            @AuthenticationPrincipal UserPrincipal currentUser) {
        log.info("Update task {} status to {} requested by user: {}", id, request.getStatus(), currentUser.getUsername());
        TaskResponse response = taskService.updateTaskStatus(id, request, currentUser.getId());
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse> deleteTask(
            @PathVariable Long id,
            @AuthenticationPrincipal UserPrincipal currentUser) {
        log.info("Delete task {} requested by user: {}", id, currentUser.getUsername());
        taskService.deleteTask(id, currentUser.getId());
        return ResponseEntity.ok(new ApiResponse(true, "Task successfully deleted"));
    }
}

