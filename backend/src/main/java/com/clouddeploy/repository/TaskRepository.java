package com.clouddeploy.repository;

import com.clouddeploy.model.Task;
import com.clouddeploy.model.TaskPriority;
import com.clouddeploy.model.TaskStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface TaskRepository extends JpaRepository<Task, Long>, JpaSpecificationExecutor<Task> {

    Optional<Task> findByIdAndUserId(Long id, Long userId);

    Page<Task> findAllByUserId(Long userId, Pageable pageable);

    Page<Task> findAllByUserIdAndStatus(Long userId, TaskStatus status, Pageable pageable);

    Page<Task> findAllByUserIdAndPriority(Long userId, TaskPriority priority, Pageable pageable);

    Page<Task> findAllByUserIdAndStatusAndPriority(Long userId, TaskStatus status, TaskPriority priority, Pageable pageable);

    boolean existsByIdAndUserId(Long id, Long userId);

    void deleteByIdAndUserId(Long id, Long userId);
}

