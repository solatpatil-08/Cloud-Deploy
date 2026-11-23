package com.clouddeploy.service;

import com.clouddeploy.dto.request.CreateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskStatusRequest;
import com.clouddeploy.dto.response.PagedResponse;
import com.clouddeploy.dto.response.TaskResponse;
import com.clouddeploy.model.TaskPriority;
import com.clouddeploy.model.TaskStatus;

public interface TaskService {

    TaskResponse createTask(CreateTaskRequest request, Long userId);

    PagedResponse<TaskResponse> getTasks(Long userId, TaskStatus status, TaskPriority priority,
                                         String search, int page, int size, String sortBy, String sortDir);

    TaskResponse getTaskById(Long id, Long userId);

    TaskResponse updateTask(Long id, UpdateTaskRequest request, Long userId);

    TaskResponse updateTaskStatus(Long id, UpdateTaskStatusRequest request, Long userId);

    void deleteTask(Long id, Long userId);
}

