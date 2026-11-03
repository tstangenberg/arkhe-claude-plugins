# Spring AOP Examples

## Contents

- [Module layout](#module-layout)
- [Public error contract](#public-error-contract)
- [Facade and internal ports](#facade-and-internal-ports)
- [Module-owned translator](#module-owned-translator)
- [Facade translation aspect](#facade-translation-aspect)
- [Translator tests](#translator-tests)
- [Spring-proxy and transaction tests](#spring-proxy-and-transaction-tests)

## Module Layout

Use this recipe in a Spring Boot 4 application rooted at `com.example`. Each public type belongs in its own named Java file. The snippets form one example, not a runnable application: supply the repository and verification-gateway adapters and the build dependencies described in [WORKFLOW.md](WORKFLOW.md).

```text
com.example.customer/                 # Modulith base package: public module API
  CustomerFacade.java
  DomainException.java               # One class: code, safe message, cause
  internal/                          # Internal to this module, even for public Java types
    CustomerRepository.java
    CustomerVerificationGateway.java
    CustomerExceptionTranslator.java
    CustomerExceptionTranslationAspect.java
```

Do not export `internal` as a named interface. A module facade may depend on its own internal implementation. Other modules should depend only on the facade and public error contract. Verify this with `ApplicationModules.of(Application.class).verify()` in the consuming application.

The example assumes the customer repository owns a uniqueness constraint named `uk_customer_email`, exposes persistence failures through Spring exception translation, and reports optimistic conflicts only for customer updates. The gateway uses a JDK HTTP-client-backed Spring RestClient and exposes `ResourceAccessException` with a direct `HttpTimeoutException` cause for the illustrated timeout. Verify that shape with the configured request factory; other clients/wrappers need their own explicit mapping.

## Public Error Contract

Use **one exception class**, not one subclass per error. Its stable code identifies the failure; its message is explicitly safe for callers. `RuntimeException` already stores the message and cause. The cause remains available to server-side handlers and is never serialized to an HTTP caller.

`DomainException.java`:

```java
package com.example.customer;

import java.util.Objects;

public final class DomainException extends RuntimeException {
    private final String code;

    public DomainException(String code, String message, Throwable cause) {
        super(Objects.requireNonNull(message, "message"), cause);
        this.code = Objects.requireNonNull(code, "code");
        if (code.isBlank() || message.isBlank()) {
            throw new IllegalArgumentException("code and message must not be blank");
        }
    }

    public String getCode() {
        return code;
    }
}
```

The example places this single class in the customer module's public API. If the application already has a common `DomainException` in a shared contract/named interface, reuse that class across module translators instead of copying it per module. Keep codes module-qualified, such as `CUSTOMER_ALREADY_EXISTS`.

Use the same class for recognized business conflicts and module-facing availability errors, with distinct codes; naming it `DomainException` does not turn a dependency outage into a business invariant violation. Do not use a provider's `getMessage()` as the safe message. The response DTO is a separate web type—see [HTTP-ERRORS.md](HTTP-ERRORS.md).

## Facade and Internal Ports

`CustomerFacade.java`:

```java
package com.example.customer;

import com.example.customer.internal.CustomerRepository;
import com.example.customer.internal.CustomerVerificationGateway;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CustomerFacade {
    private final CustomerRepository repository;
    private final CustomerVerificationGateway gateway;

    CustomerFacade(CustomerRepository repository, CustomerVerificationGateway gateway) {
        this.repository = repository;
        this.gateway = gateway;
    }

    @Transactional
    public UUID register(String email) {
        return repository.register(email);
    }

    @Transactional
    public void updateEmail(UUID customerId, String email) {
        repository.updateEmail(customerId, email);
    }

    public void verify(UUID customerId) {
        gateway.verify(customerId);
    }
}
```

`CustomerRepository.java`:

```java
package com.example.customer.internal;

import java.util.UUID;

public interface CustomerRepository {
    UUID register(String email);
    void updateEmail(UUID customerId, String email);
}
```

`CustomerVerificationGateway.java`:

```java
package com.example.customer.internal;

import java.util.UUID;

public interface CustomerVerificationGateway {
    void verify(UUID customerId);
}
```

The internal gateway adapter may expose Spring client types, but the public facade no longer declares a client-specific checked exception. The translator recognizes only the demonstrated timeout cause beneath `ResourceAccessException`. Other I/O failures remain unchanged; retain interruption semantics rather than disguising interruption as a verification timeout.

## Module-Owned Translator

`CustomerExceptionTranslator.java`:

```java
package com.example.customer.internal;

import com.example.customer.DomainException;
import java.net.http.HttpTimeoutException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;

@Component
public class CustomerExceptionTranslator {
    public Exception translate(Exception failure) {
        if (failure instanceof DomainException) {
            return failure;
        }

        if (failure instanceof DataIntegrityViolationException
                && failure.getCause() instanceof
                    org.hibernate.exception.ConstraintViolationException constraint) {
            if ("uk_customer_email".equals(constraint.getConstraintName())) {
                return new DomainException("CUSTOMER_ALREADY_EXISTS",
                    "A customer with this email already exists", failure);
            }
        }

        // Valid only because this facade's persistence operations own customer updates.
        if (failure instanceof OptimisticLockingFailureException) {
            return new DomainException("CUSTOMER_CONCURRENT_MODIFICATION",
                "The customer was modified concurrently", failure);
        }

        // This facade's sole RestClient integration is customer verification.
        if (failure instanceof ResourceAccessException
                && failure.getCause() instanceof HttpTimeoutException) {
            return new DomainException("CUSTOMER_VERIFICATION_UNAVAILABLE",
                "Customer verification is temporarily unavailable", failure);
        }

        // Includes already-translated validation/other-module errors and unknown failures.
        return failure;
    }
}
```

The Hibernate type here is **`org.hibernate.exception.ConstraintViolationException`**, not Jakarta Bean Validation's similarly named exception. `getConstraintName()` is structured but nullable/provider-dependent metadata. Use an exact known identifier; account deliberately for quoting/schema conventions if your provider reports them differently.

The matcher inspects only the direct Hibernate cause of Spring's integrity exception. It does not descend through arbitrary module exceptions or transaction wrappers. If the real provider emits another supported shape, add a bounded, explicit rule with an integration test. Preserve the original caught failure, including its wrapper, as the mapped exception's cause.

Unknown constraints, unknown technical failures, and errors from another module remain unchanged. Do not add an `Exception -> CUSTOMER_ALREADY_EXISTS` fallback or map by SQL message text.

## Facade Translation Aspect

`CustomerExceptionTranslationAspect.java`:

```java
package com.example.customer.internal;

import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

@Aspect
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class CustomerExceptionTranslationAspect {
    private final CustomerExceptionTranslator translator;

    public CustomerExceptionTranslationAspect(CustomerExceptionTranslator translator) {
        this.translator = translator;
    }

    @Around("execution(public * com.example.customer.CustomerFacade.*(..))")
    public Object translate(ProceedingJoinPoint call) throws Throwable {
        try {
            return call.proceed();
        } catch (Exception failure) {
            throw translator.translate(failure);
        }
    }
}
```

Catch `Exception`, not `Throwable`: the declared `throws Throwable` accommodates `proceed()`, but JVM `Error` types propagate without translation. Successful values and unmapped exception instances are preserved.

This order leaves room for the existing validation translation aspect at `HIGHEST_PRECEDENCE` and surrounds transaction advice at its default `LOWEST_PRECEDENCE`, when they are in the same advisor chain. The general translator has no validation mapping; it passes validation failures through so the validation aspect can own them. Verify method-validation post-processor/proxy arrangements in the application; numeric order alone does not prove the full chain.

## Translator Tests

Use JUnit Jupiter and AssertJ from the consuming application's test dependencies. Place these test methods in a test class in `com.example.customer.internal`; import JUnit's `Test`, AssertJ's static `assertThat`, `com.example.customer.DomainException`, `java.sql.SQLException`, `java.net.http.HttpTimeoutException`, Spring's DAO types, and `org.springframework.web.client.ResourceAccessException`.

```java
@Test
void mapsOnlyTheKnownConstraintAndPreservesTheCaughtCause() {
    var translator = new CustomerExceptionTranslator();
    var sql = new SQLException("diagnostic only", "23505");
    var hibernate = new org.hibernate.exception.ConstraintViolationException(
        "insert failed", sql, "uk_customer_email");
    var original = new DataIntegrityViolationException("insert failed", hibernate);

    var mapped = (DomainException) translator.translate(original);
    assertThat(mapped.getCode()).isEqualTo("CUSTOMER_ALREADY_EXISTS");
    assertThat(mapped.getMessage()).isEqualTo("A customer with this email already exists");
    assertThat(mapped).hasCause(original);
}

@Test
void leavesUnknownConstraintsAndAlreadyTranslatedErrorsUnchanged() {
    var translator = new CustomerExceptionTranslator();
    var hibernate = new org.hibernate.exception.ConstraintViolationException(
        "insert failed", new SQLException(), "fk_customer_account");
    var unknown = new DataIntegrityViolationException("insert failed", hibernate);
    var translated = new DomainException("CUSTOMER_ALREADY_EXISTS",
        "A customer with this email already exists", unknown);

    assertThat(translator.translate(unknown)).isSameAs(unknown);
    assertThat(translator.translate(translated)).isSameAs(translated);
}

@Test
void mapsConcurrencyAndVerificationAvailabilityButNotArbitraryFailures() {
    var translator = new CustomerExceptionTranslator();
    var conflict = new OptimisticLockingFailureException("stale version");
    var timeout = new ResourceAccessException("verification request failed",
        new HttpTimeoutException("request timed out"));
    var unknown = new IllegalStateException("unexpected failure");

    var concurrencyError = (DomainException) translator.translate(conflict);
    assertThat(concurrencyError.getCode()).isEqualTo("CUSTOMER_CONCURRENT_MODIFICATION");
    assertThat(concurrencyError).hasCause(conflict);
    var availabilityError = (DomainException) translator.translate(timeout);
    assertThat(availabilityError.getCode()).isEqualTo("CUSTOMER_VERIFICATION_UNAVAILABLE");
    assertThat(availabilityError).hasCause(timeout);
    assertThat(translator.translate(unknown)).isSameAs(unknown);
}
```

Also cover null constraint metadata, unwrapped SQL exceptions, already-translated validation errors, other-module errors with nested SQL causes, and known transaction wrapper shapes if your application supports them.

## Spring-Proxy and Transaction Tests

Test the injected facade, not a `new CustomerFacade(...)` instance or a direct call to the aspect. Use a minimal Spring configuration with the following ingredients:

- `@EnableAspectJAutoProxy(proxyTargetClass = true)` and `@EnableTransactionManagement`.
- Beans for the facade, translator, aspect, repository stub, gateway stub, and transaction manager.
- Assert `AopUtils.isAopProxy(facade)` before testing behavior.
- Keep the test method non-transactional so `facade.register()` owns transaction completion.

Assert that a successful call returns the repository's UUID unchanged, a repository-body failure is translated, an unknown failure is rethrown as the **same instance**, and an `AssertionError` passes through unchanged.

For a commit-ordering test, use an `AbstractPlatformTransactionManager` test double whose service body succeeds but whose `doCommit(DefaultTransactionStatus)` throws a known persistence failure. Assert that the facade call produces the mapped exception with that commit failure as its cause. This tests advice ordering, not real database behavior.

A separate real persistence integration test should trigger the actual constraint at flush/commit and verify the observed Spring/Hibernate exception shape. Do not infer provider behavior from a mocked repository or a synthetic transaction manager.

For a joined-transaction test, invoke the facade inside a caller's `TransactionTemplate`. Use a transaction manager that recognizes the existing transaction. Assert that the final commit failure escapes at the **caller** boundary without passing through the facade aspect again. Do not fix that result with `REQUIRES_NEW`; it is the documented boundary limitation.

For validation coexistence, run the actual `@Validated` bean through its Spring proxy and assert the validation aspect's public error is not wrapped again. Inspect `Advised.getAdvisors()` when diagnosing the chain.

See [TESTING.md](TESTING.md) for the complete Spring-proxy test class and synthetic commit/joining tests. These are instructional test snippets and test requirements, not an executed Java test suite in this plugin repository.
