package com.clouddeploy.service.impl;

import com.clouddeploy.dto.request.CreateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskRequest;
import com.clouddeploy.dto.request.UpdateTaskStatusRequest;
import com.clouddeploy.dto.response.PagedResponse;
import com.clouddeploy.dto.response.TaskResponse;
import com.clouddeploy.exception.BadRequestException;
import com.clouddeploy.exception.ResourceNotFoundException;
import com.clouddeploy.model.Task;
import com.clouddeploy.model.TaskPriority;
import com.clouddeploy.model.TaskStatus;
import com.clouddeploy.model.User;
import com.clouddeploy.repository.TaskRepository;
import com.clouddeploy.repository.UserRepository;
import com.clouddeploy.service.TaskService;
import jakarta.persistence.criteria.Predicate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;

@Service
public class TaskServiceImpl implements TaskService {

    private static final Logger log = LoggerFactory.getLogger(TaskServiceImpl.class);
    private static final Set<String> ALLOWED_SORT_FIELDS = Set.of(
            "id", "title", "status", "priority", "dueDate", "createdAt", "updatedAt"
    );

    private final TaskRepository taskRepository;
    private final UserRepository userRepository;

    public TaskServiceImpl(TaskRepository taskRepository, UserRepository userRepository) {
        this.taskRepository = taskRepository;
        this.userRepository = userRepository;
    }

    @Override
    @Transactional
    public TaskResponse createTask(CreateTaskRequest request, Long userId) {
        log.info("Creating task for user id {}: {}", userId, request.getTitle());

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User", "id", userId));

        Task task = new Task(
                request.getTitle().trim(),
                request.getDescription() != null ? request.getDescription().trim() : null,
                request.getStatus(),
                request.getPriority(),
                request.getDueDate(),
                user
        );

        Task savedTask = taskRepository.save(task);
        log.info("Successfully created task id {} for user id {}", savedTask.getId(), userId);

        return TaskResponse.fromEntity(savedTask);
    }

    @Override
    @Transactional(readOnly = true)
    public PagedResponse<TaskResponse> getTasks(Long userId, TaskStatus status, TaskPriority priority,
                                                String search, int page, int size, String sortBy, String sortDir) {
        log.debug("Fetching tasks for user id {}: status={}, priority={}, page={}, size={}",
                userId, status, priority, page, size);

        validatePaginationAndSorting(page, size, sortBy, sortDir);

        Sort.Direction direction = sortDir.equalsIgnoreCase("desc") ? Sort.Direction.DESC : Sort.Direction.ASC;
        Pageable pageable = PageRequest.of(page, size, Sort.by(direction, sortBy));

        Specification<Task> spec = (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();

            // Enforce strict user isolation
            predicates.add(cb.equal(root.get("user").get("id"), userId));

            // Status filter
            if (status != null) {
                predicates.add(cb.equal(root.get("status"), status));
            }

            // Priority filter
            if (priority != null) {
                predicates.add(cb.equal(root.get("priority"), priority));
            }

            // Search filter across title or description
            if (StringUtils.hasText(search)) {
                String searchPattern = "%" + search.toLowerCase().trim() + "%";
                Predicate titlePredicate = cb.like(cb.lower(root.get("title")), searchPattern);
                Predicate descPredicate = cb.like(cb.lower(root.get("description")), searchPattern);
                predicates.add(cb.or(titlePredicate, descPredicate));
            }

            return cb.and(predicates.toArray(new Predicate[0]));
        };

        Page<Task> taskPage = taskRepository.findAll(spec, pageable);
        List<TaskResponse> content = taskPage.getContent().stream()
                .map(TaskResponse::fromEntity)
                .toList();

        return new PagedResponse<>(
                content,
                taskPage.getNumber(),
                taskPage.getSize(),
                taskPage.getTotalElements(),
                taskPage.getTotalPages(),
                taskPage.isLast()
        );
    }

    @Override
    @Transactional(readOnly = true)
    public TaskResponse getTaskById(Long id, Long userId) {
        log.debug("Fetching task id {} for user id {}", id, userId);

        Task task = taskRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Task", "id", id));

        return TaskResponse.fromEntity(task);
    }

    @Override
    @Transactional
    public TaskResponse updateTask(Long id, UpdateTaskRequest request, Long userId) {
        log.info("Updating task id {} for user id {}", id, userId);

        Task task = taskRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Task", "id", id));

        task.setTitle(request.getTitle().trim());
        task.setDescription(request.getDescription() != null ? request.getDescription().trim() : null);
        task.setStatus(request.getStatus());
        task.setPriority(request.getPriority());
        task.setDueDate(request.getDueDate());

        Task updatedTask = taskRepository.save(task);
        log.info("Successfully updated task id {}", updatedTask.getId());

        return TaskResponse.fromEntity(updatedTask);
    }

    @Override
    @Transactional
    public TaskResponse updateTaskStatus(Long id, UpdateTaskStatusRequest request, Long userId) {
        log.info("Updating status for task id {} to {} for user id {}", id, request.getStatus(), userId);

        Task task = taskRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Task", "id", id));

        task.setStatus(request.getStatus());

        Task updatedTask = taskRepository.save(task);
        log.info("Successfully updated status of task id {}", updatedTask.getId());

        return TaskResponse.fromEntity(updatedTask);
    }

    @Override
    @Transactional
    public void deleteTask(Long id, Long userId) {
        log.info("Deleting task id {} for user id {}", id, userId);

        Task task = taskRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Task", "id", id));

        taskRepository.delete(task);
        log.info("Successfully deleted task id {}", id);
    }

    private void validatePaginationAndSorting(int page, int size, String sortBy, String sortDir) {
        if (page < 0) {
            throw new BadRequestException("Page number cannot be less than zero.");
        }
        if (size <= 0 || size > 100) {
            throw new BadRequestException("Page size must be between 1 and 100.");
        }
        if (!ALLOWED_SORT_FIELDS.contains(sortBy)) {
            throw new BadRequestException("Invalid sort field: '" + sortBy + "'. Allowed fields are: " + ALLOWED_SORT_FIELDS);
        }
        if (!sortDir.equalsIgnoreCase("asc") && !sortDir.equalsIgnoreCase("desc")) {
            throw new BadRequestException("Sort direction must be 'asc' or 'desc'.");
        }
    }
}

