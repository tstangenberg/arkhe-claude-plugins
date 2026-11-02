# Testing Facade Aspects Through Spring Proxies

## Scope and Setup

This JUnit Jupiter test accompanies the Java module types in [EXAMPLES.md](EXAMPLES.md). Copy those types into separate named files and supply the consuming application's Boot-managed Spring, AspectJ, Hibernate, JUnit Jupiter, and AssertJ dependencies. The test uses an explicit Framework context, not Boot auto-configuration.

The transaction manager is a **test double**, not a production resource manager. Its thread-local state models `REQUIRED` joining well enough to demonstrate where commit happens. Its `doCommit` failure verifies advice ordering; it does not verify database/provider behavior.

Place `CustomerFacadeAspectTest.java` in `com.example.customer`, so it can construct the example facade. Do not annotate this test with `@Transactional`.

## Proxy, Pass-Through, and Commit Tests

```java
package com.example.customer;

import com.example.customer.internal.CustomerExceptionTranslationAspect;
import com.example.customer.internal.CustomerExceptionTranslator;
import com.example.customer.internal.CustomerRepository;
import com.example.customer.internal.CustomerVerificationGateway;
import java.sql.SQLException;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.aop.support.AopUtils;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.EnableAspectJAutoProxy;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CustomerFacadeAspectTest {
    private AnnotationConfigApplicationContext context;
    private CustomerFacade facade;
    private RepositoryStub repository;
    private CommitTestTransactionManager transactions;

    @BeforeEach
    void startContext() {
        context = new AnnotationConfigApplicationContext(TestConfig.class);
        facade = context.getBean(CustomerFacade.class);
        repository = context.getBean(RepositoryStub.class);
        transactions = context.getBean(CommitTestTransactionManager.class);
        assertThat(AopUtils.isAopProxy(facade)).isTrue();
    }

    @AfterEach
    void closeContext() {
        context.close();
    }

    @Test
    void preservesSuccessfulReturnValue() {
        assertThat(facade.register("customer@example.test"))
            .isEqualTo(repository.customerId);
        assertThat(repository.calls).isEqualTo(1);
        assertThat(transactions.commits).isEqualTo(1);
    }

    @Test
    void translatesBodyFailureAndPreservesCause() {
        var original = knownConstraintFailure();
        repository.failure = original;

        assertThatThrownBy(() -> facade.register("customer@example.test"))
            .isInstanceOf(DomainException.class).hasCause(original)
            .satisfies(failure -> assertThat(((DomainException) failure).getCode())
                .isEqualTo("CUSTOMER_ALREADY_EXISTS"));
        assertThat(transactions.commits).isZero();
    }

    @Test
    void preservesUnknownAndAlreadyTranslatedExceptionIdentity() {
        var unknown = new IllegalStateException("unexpected");
        repository.failure = unknown;
        assertThatThrownBy(() -> facade.register("customer@example.test"))
            .isSameAs(unknown);

        var translated = new DomainException("CUSTOMER_ALREADY_EXISTS",
            "A customer with this email already exists", unknown);
        repository.failure = translated;
        assertThatThrownBy(() -> facade.register("customer@example.test"))
            .isSameAs(translated);
    }

    @Test
    void doesNotTranslateJvmErrors() {
        var error = new AssertionError("test error");
        repository.error = error;
        assertThatThrownBy(() -> facade.register("customer@example.test"))
            .isSameAs(error);
    }

    @Test
    void translatesFailureAfterTheTargetReturnsAtCommit() {
        var commitFailure = knownConstraintFailure();
        transactions.commitFailure = commitFailure;

        assertThatThrownBy(() -> facade.register("customer@example.test"))
            .isInstanceOf(DomainException.class).hasCause(commitFailure)
            .satisfies(failure -> assertThat(((DomainException) failure).getCode())
                .isEqualTo("CUSTOMER_ALREADY_EXISTS"));
        assertThat(repository.calls).isEqualTo(1); // body succeeded
        assertThat(transactions.commits).isEqualTo(1); // doCommit failed
    }

    @Test
    void callerOwnedCommitHappensOutsideFacadeTranslation() {
        var commitFailure = knownConstraintFailure();
        transactions.commitFailure = commitFailure;
        var facadeReturned = new AtomicBoolean();
        var callerTransaction = new TransactionTemplate(transactions);

        assertThatThrownBy(() -> callerTransaction.execute(status -> {
            assertThat(facade.register("customer@example.test"))
                .isEqualTo(repository.customerId);
            assertThat(transactions.commits).isZero();
            facadeReturned.set(true);
            return null;
        })).isSameAs(commitFailure); // not translated by the already-returned facade

        assertThat(facadeReturned).isTrue();
        assertThat(transactions.commits).isEqualTo(1);
    }

    private static DataIntegrityViolationException knownConstraintFailure() {
        var provider = new org.hibernate.exception.ConstraintViolationException(
            "insert failed", new SQLException("diagnostic", "23505"),
            "uk_customer_email");
        return new DataIntegrityViolationException("insert failed", provider);
    }

    @Configuration(proxyBeanMethods = false)
    @EnableAspectJAutoProxy(proxyTargetClass = true)
    @EnableTransactionManagement
    static class TestConfig {
        @Bean
        RepositoryStub repository() {
            return new RepositoryStub();
        }

        @Bean
        CustomerVerificationGateway gateway() {
            return customerId -> {};
        }

        @Bean
        CustomerFacade facade(RepositoryStub repository,
                CustomerVerificationGateway gateway) {
            return new CustomerFacade(repository, gateway);
        }

        @Bean
        CustomerExceptionTranslator translator() {
            return new CustomerExceptionTranslator();
        }

        @Bean
        CustomerExceptionTranslationAspect translationAspect(
                CustomerExceptionTranslator translator) {
            return new CustomerExceptionTranslationAspect(translator);
        }

        @Bean
        CommitTestTransactionManager transactionManager() {
            return new CommitTestTransactionManager();
        }
    }

    static class RepositoryStub implements CustomerRepository {
        final UUID customerId = UUID.randomUUID();
        int calls;
        RuntimeException failure;
        Error error;

        public UUID register(String email) {
            calls++;
            if (error != null) throw error;
            if (failure != null) throw failure;
            return customerId;
        }

        public void updateEmail(UUID customerId, String email) {}
    }

    static class CommitTestTransactionManager extends AbstractPlatformTransactionManager {
        private final ThreadLocal<TestTransaction> current = new ThreadLocal<>();
        RuntimeException commitFailure;
        int commits;

        protected Object doGetTransaction() {
            var existing = current.get();
            return existing != null ? existing : new TestTransaction();
        }

        protected boolean isExistingTransaction(Object transaction) {
            return ((TestTransaction) transaction).active;
        }

        protected void doBegin(Object transaction, TransactionDefinition definition) {
            var tx = (TestTransaction) transaction;
            tx.active = true;
            current.set(tx);
        }

        protected void doCommit(DefaultTransactionStatus status) {
            commits++;
            if (commitFailure != null) throw commitFailure;
        }

        protected void doRollback(DefaultTransactionStatus status) {}

        protected void doCleanupAfterCompletion(Object transaction) {
            ((TestTransaction) transaction).active = false;
            current.remove();
        }

        private static class TestTransaction {
            boolean active;
        }
    }
}
```

This double only models the successful joining path plus body/commit failures used above. It does not implement suspension, savepoints, resource cleanup, or rollback-only propagation for every possible nested failure. Do not use it to evaluate other transaction propagation modes.

## Additional Application Tests

- Use [HTTP-ERRORS.md](HTTP-ERRORS.md) for the code/message-only DTO tests and server-side cause logging assertions. Do not mistake a preserved exception cause in Java tests for permission to serialize it to HTTP callers.

- Add a real persistence integration test to establish whether the driver/provider reports `uk_customer_email` and how it wraps flush/commit failures. Verify unknown/null constraint names pass through.
- Use translator unit tests from [EXAMPLES.md](EXAMPLES.md) for optimistic locking and the specific verification timeout. Extend facade tests with a failing gateway stub if that mapping is used in production.
- Exercise the application's actual `@Validated` bean and validation translation aspect together. Assert validation error identity/ownership and inspect `Advised.getAdvisors()` if ordering differs from expectations.
- Add `ApplicationModules.of(Application.class).verify()` to check public versus internal module dependencies. That verification does not prove pointcut matching or exception translation.

These examples are supplied as instructional tests; running repository Markdown/skill validation is not the same as executing this Java suite.
