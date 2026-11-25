package com.clouddeploy.repository;

import com.clouddeploy.model.Task;
import com.clouddeploy.model.TaskPriority;
import com.clouddeploy.model.TaskStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface TaskRepository extends JpaRepository<Task, Long>, JpaSpecificationExecutor<Task> {

    @Query("SELECT t FROM Task t WHERE t.id = :id AND t.user.id = :userId")
    Optional<Task> findByIdAndUserId(@Param("id") Long id, @Param("userId") Long userId);

    @Query("SELECT t FROM Task t WHERE t.user.id = :userId")
    Page<Task> findAllByUserId(@Param("userId") Long userId, Pageable pageable);

    @Query("SELECT t FROM Task t WHERE t.user.id = :userId AND t.status = :status")
    Page<Task> findAllByUserIdAndStatus(@Param("userId") Long userId, @Param("status") TaskStatus status, Pageable pageable);

    @Query("SELECT t FROM Task t WHERE t.user.id = :userId AND t.priority = :priority")
    Page<Task> findAllByUserIdAndPriority(@Param("userId") Long userId, @Param("priority") TaskPriority priority, Pageable pageable);

    @Query("SELECT t FROM Task t WHERE t.user.id = :userId AND t.status = :status AND t.priority = :priority")
    Page<Task> findAllByUserIdAndStatusAndPriority(@Param("userId") Long userId, @Param("status") TaskStatus status, @Param("priority") TaskPriority priority, Pageable pageable);

    @Query("SELECT COUNT(t) > 0 FROM Task t WHERE t.id = :id AND t.user.id = :userId")
    boolean existsByIdAndUserId(@Param("id") Long id, @Param("userId") Long userId);

    @Modifying
    @Query("DELETE FROM Task t WHERE t.id = :id AND t.user.id = :userId")
    void deleteByIdAndUserId(@Param("id") Long id, @Param("userId") Long userId);
}
