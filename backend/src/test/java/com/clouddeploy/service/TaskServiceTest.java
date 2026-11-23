package com.clouddeploy.service;

import com.clouddeploy.dto.request.CreateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskStatusRequest;
import com.clouddeploy.dto.response.PagedResponse;
import com.clouddeploy.dto.response.TaskResponse;
import com.clouddeploy.exception.BadRequestException;
import com.clouddeploy.exception.ResourceNotFoundException;
import com.clouddeploy.model.Role;
import com.clouddeploy.model.Task;
import com.clouddeploy.model.TaskPriority;
import com.clouddeploy.model.TaskStatus;
import com.clouddeploy.model.User;
import com.clouddeploy.repository.TaskRepository;
import com.clouddeploy.repository.UserRepository;
import com.clouddeploy.service.impl.TaskServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;

import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TaskServiceTest {

    @Mock
    private TaskRepository taskRepository;

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private TaskServiceImpl taskService;

    private User owner;
    private Task task;

    @BeforeEach
    void setUp() {
        owner = new User("task_owner", "owner@example.com", "pass", Role.ROLE_USER);
        owner.setId(1L);

        task = new Task("Deploy App", "Deploy to AWS EC2", TaskStatus.TODO, TaskPriority.HIGH, Instant.now().plusSeconds(86400), owner);
        task.setId(100L);
    }

    @Test
    @DisplayName("Should successfully create a task for authenticated user")
    void testCreateTaskSuccess() {
        CreateTaskRequest request = new CreateTaskRequest(
                "Deploy App", "Deploy to AWS EC2", TaskStatus.TODO, TaskPriority.HIGH, Instant.now()
        );

        when(userRepository.findById(1L)).thenReturn(Optional.of(owner));
        when(taskRepository.save(any(Task.class))).thenReturn(task);

        TaskResponse response = taskService.createTask(request, 1L);

        assertNotNull(response);
        assertEquals(100L, response.getId());
        assertEquals("Deploy App", response.getTitle());
        assertEquals(TaskStatus.TODO, response.getStatus());
        assertEquals(1L, response.getUserId());

        verify(taskRepository, times(1)).save(any(Task.class));
    }

    @Test
    @DisplayName("Should fetch task by id when owned by user")
    void testGetTaskByIdSuccess() {
        when(taskRepository.findByIdAndUserId(100L, 1L)).thenReturn(Optional.of(task));

        TaskResponse response = taskService.getTaskById(100L, 1L);

        assertNotNull(response);
        assertEquals(100L, response.getId());
        assertEquals("Deploy App", response.getTitle());
    }

    @Test
    @DisplayName("Should throw ResourceNotFoundException when task does not belong to requesting user")
    void testGetTaskByIdUnowned() {
        when(taskRepository.findByIdAndUserId(100L, 2L)).thenReturn(Optional.empty());

        assertThrows(ResourceNotFoundException.class, () -> taskService.getTaskById(100L, 2L));
    }

    @Test
    @DisplayName("Should fetch paged tasks for user")
    void testGetTasksPaged() {
        Page<Task> page = new PageImpl<>(List.of(task));
        when(taskRepository.findAll(any(Specification.class), any(Pageable.class))).thenReturn(page);

        PagedResponse<TaskResponse> response = taskService.getTasks(
                1L, null, null, null, 0, 10, "createdAt", "desc"
        );

        assertNotNull(response);
        assertEquals(1, response.getContent().size());
        assertEquals(100L, response.getContent().get(0).getId());
    }

    @Test
    @DisplayName("Should reject invalid sort field")
    void testGetTasksInvalidSortField() {
        assertThrows(BadRequestException.class, () -> taskService.getTasks(
                1L, null, null, null, 0, 10, "hackedField", "desc"
        ));
    }

    @Test
    @DisplayName("Should successfully update task fields")
    void testUpdateTask() {
        UpdateTaskRequest updateRequest = new UpdateTaskRequest(
                "Updated Title", "Updated Description", TaskStatus.IN_PROGRESS, TaskPriority.LOW, Instant.now()
        );

        when(taskRepository.findByIdAndUserId(100L, 1L)).thenReturn(Optional.of(task));
        when(taskRepository.save(any(Task.class))).thenReturn(task);

        TaskResponse response = taskService.updateTask(100L, updateRequest, 1L);

        assertNotNull(response);
        assertEquals("Updated Title", task.getTitle());
        assertEquals(TaskStatus.IN_PROGRESS, task.getStatus());
        assertEquals(TaskPriority.LOW, task.getPriority());
    }

    @Test
    @DisplayName("Should successfully update task status")
    void testUpdateTaskStatus() {
        UpdateTaskStatusRequest statusRequest = new UpdateTaskStatusRequest(TaskStatus.COMPLETED);

        when(taskRepository.findByIdAndUserId(100L, 1L)).thenReturn(Optional.of(task));
        when(taskRepository.save(any(Task.class))).thenReturn(task);

        TaskResponse response = taskService.updateTaskStatus(100L, statusRequest, 1L);

        assertNotNull(response);
        assertEquals(TaskStatus.COMPLETED, task.getStatus());
    }

    @Test
    @DisplayName("Should successfully delete task owned by user")
    void testDeleteTaskSuccess() {
        when(taskRepository.findByIdAndUserId(100L, 1L)).thenReturn(Optional.of(task));
        doNothing().when(taskRepository).delete(task);

        assertDoesNotThrow(() -> taskService.deleteTask(100L, 1L));
        verify(taskRepository, times(1)).delete(task);
    }

    @Test
    @DisplayName("Should throw ResourceNotFoundException when deleting task owned by another user")
    void testDeleteTaskUnowned() {
        when(taskRepository.findByIdAndUserId(100L, 999L)).thenReturn(Optional.empty());

        assertThrows(ResourceNotFoundException.class, () -> taskService.deleteTask(100L, 999L));
        verify(taskRepository, never()).delete(any(Task.class));
    }
}

