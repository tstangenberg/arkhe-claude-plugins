# Spring Boot AOP Workflow

## 1. Inspect the Application and Enable AOP

Read the Boot version and dependency management before adding dependencies. For **Spring Boot 4**, use the renamed starter, with its version supplied by the Boot BOM:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aspectj</artifactId>
</dependency>
```

Gradle equivalent:

```kotlin
implementation("org.springframework.boot:spring-boot-starter-aspectj")
```

Boot 3 uses `spring-boot-starter-aop`; do not copy that name into a Boot 4 example. The Boot 4 starter provides Spring AOP and AspectJ support for annotation/pointcut parsing. It does **not** enable AspectJ bytecode weaving or require a Java agent.

Under normal Boot auto-configuration, AspectJ on the classpath enables auto-proxy support. Register each aspect as a Spring bean using `@Component` or `@Bean`; `@Aspect` alone does not register it. A minimal non-Boot test context uses `@EnableAspectJAutoProxy` explicitly. Ordinary `@Transactional` support does not itself require a custom AspectJ aspect.

Inspect existing `spring.aop.*` settings, advice, transaction configuration, validation post-processors, and any actual weaving configuration. Boot defaults to class-based proxies; `spring.aop.proxy-target-class=false` requests JDK proxies. Do not assume a plain Framework test context has Boot's proxy defaults.

## 2. Choose the Boundary and Pointcut

Start with **public facade methods in one module**, not every repository, service, or module internal. For the example's concrete `CustomerFacade`:

```java
@Around("execution(public * com.example.customer.CustomerFacade.*(..))")
```

If the facade is an interface, target that public contract deliberately and test the implementation through the selected proxy type. `target(Type)` refers to the underlying target, while `this(Type)` refers to the proxy; `this(ConcreteImplementation)` is not portable to JDK proxies.

A pointcut is a selection rule, not an architectural boundary enforcer. In Modulith, put the public facade/error types in the module's base package or an exposed named interface, and keep the aspect/translator in an internal subpackage. Verify module structure separately.

### Explicit opt-in alternative

For multiple facade classes, define a runtime, type-targeted annotation inside the module's internal package:

```java
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface CustomerFacadeBoundary {}
```

Use imports from `java.lang.annotation`. Annotate each **concrete Spring target class**, then combine annotation matching with a module scope:

```java
@Around("execution(public * com.example.customer..*(..)) && "
    + "@within(com.example.customer.internal.CustomerFacadeBoundary)")
```

`@within` selects executions in annotated types; `@annotation` selects annotated methods. A method annotation needs `@Target(METHOD)` and a corresponding pointcut. Do not assume interface annotations are inherited onto implementation classes, or that a composed annotation is automatically matched as its meta-annotation. Test the placement you actually use.

Keep translator/aspect beans outside the selected targets to avoid recursive interception. Do not use `@Validated` as the general facade marker: it denotes validation, not ownership of a module's technical error contract.

## 3. Choose Advice and Preserve Behavior

| Need | Advice |
|------|--------|
| Observe before a call | `@Before` |
| Observe a successful result | `@AfterReturning` |
| Observe a thrown failure without replacing it | `@AfterThrowing` |
| Cleanup regardless of outcome | `@After` |
| Translate a failure or control invocation | `@Around` |

Use `@Around` for the exception translation recipe. Call `ProceedingJoinPoint.proceed()` once, return its value unchanged, and catch `Exception` rather than JVM `Error` types. The advice can declare `throws Throwable` because `proceed()` does; this does not require catching `Throwable`.

Do not swallow exceptions, retry implicitly, modify arguments, or start new transactions as part of translation. Interruption must retain its semantics; do not map an interrupted operation to an ordinary business failure.

## 4. Define the Module Translation Policy

Write a module-owned translator bean returning one `DomainException(code, message, cause)` for recognized failures, not one subclass per mapping. Reuse an existing common exception class if present; the example declares it in the module's public API. Keep codes stable and module-qualified and messages curated for callers. Let the translator depend on persistence/client types while keeping code/message framework-free. Retain the original caught failure as the exception superclass's `Throwable` cause; exclude provider text, SQL, invalid values, and stack traces from public messages/response fields.

Document each rule:

| Recognized failure | Meaning in this module | Evidence required |
|--------------------|------------------------|-------------------|
| Customer email uniqueness violation | Customer already exists | Known constraint identifier from structured metadata |
| Optimistic-locking conflict on a customer update | Concurrent customer modification | Operation/resource ownership established |
| Customer verification HTTP timeout | Verification unavailable | Specific client exception and integration scope |
| Unrecognized SQL/client failure | Unexpected technical failure | No mapping: return the original instance |

Prefer Spring's `DataAccessException` hierarchy for Spring-managed persistence. A raw `SQLException`, a Spring DAO exception, and a transaction wrapper are different observable contracts; inspect the real integration rather than catch them interchangeably.

In Hibernate, `org.hibernate.exception.ConstraintViolationException.getConstraintName()` is nullable structured database metadata. It is distinct from Jakarta Bean Validation's exception. Do not infer the rule from arbitrary SQL message text or SQLState class `23` alone.

The [example](EXAMPLES.md) supports a direct Hibernate cause beneath `DataIntegrityViolationException`, and a direct JDK `HttpTimeoutException` cause beneath RestClient's `ResourceAccessException` for its sole verification integration. Neither shape is universal; verify both against the actual adapters. Some JPA/JDBC commit paths translate directly to DAO exceptions; others expose wrappers such as `TransactionSystemException`. Add a wrapper mapping only for a recognized, tested structure. Its `getOriginalException()` may hold information not represented by its ordinary cause. Do not traverse arbitrary causes and remap another module's error merely because a SQL failure appears deep inside it.

Preserve already-translated module errors and unknown failures unchanged. A closed module error contract is a separate decision; do not introduce a generic business-error fallback without that requirement.

## 5. Arrange Advice Around Transactions and Validation

Lower order values have higher precedence: earlier on entry, later on exit. In a shared advisor chain, the example uses:

```text
validation translation: HIGHEST_PRECEDENCE (when applicable)
  module translation: HIGHEST_PRECEDENCE + 10
    transaction advice: LOWEST_PRECEDENCE (default)
      target invocation, with method validation wherever its actual advisor is installed
```

The general translator deliberately does not map validation exceptions. If it encounters one, it rethrows the same instance so the validation translator can own the replacement. Already-translated errors also remain unchanged. Do not give overlapping translation aspects equal orders and assume a relative order.

`@EnableTransactionManagement(order = ...)` controls transaction advice's order; putting `@Order` on a service class does not. An outer translator observes target-body and transaction-completion failures **only when completion occurs inside its `proceed()` call**. Inner advice can still see the original failure; there is no guarantee that every aspect sees the replacement.

### Transaction ownership limit

With default `REQUIRED` propagation, a facade may join its caller's transaction. Its aspect returns before the caller later commits. That later failure is outside this translation boundary. Do not add `REQUIRES_NEW` or force a flush solely to hide the limit; these change business transaction semantics, and flush is not final commit.

### Method validation limit

`MethodValidationPostProcessor#setOrder` orders the **bean post-processor**, not simply its validation interceptor. `setBeforeExistingAdvisors` and existing/nested proxies affect advisor placement. Default service validation raises Jakarta's `ConstraintViolationException`; adapted validation can raise Spring's `MethodValidationException` instead. Keep that policy in [spring-boot-bean-validation](../spring-boot-bean-validation/SKILL.md).

Inspect `Advised.getAdvisors()` and test the actual Spring-managed beans. Do not infer a complete advisor chain solely from `@Order` annotations.

## 6. Test the Policy and Interception Separately

1. **Translator unit tests:** known constraint, unknown/null constraint metadata, optimistic conflict, specific client timeout, existing `DomainException`, and unknown failure. Assert code, safe message, preserved causes, and identity for pass-through.
2. **Spring-proxy tests:** injected facade, `AopUtils.isAopProxy`, successful return unchanged, body failure mapped, unknown failure unchanged, and `Error` unchanged.
3. **Commit-order test:** a synthetic transaction manager throws from `doCommit(DefaultTransactionStatus)` after the facade body succeeds. Do not annotate the test with `@Transactional`.
4. **Provider integration test:** a real database constraint verifies the actual metadata/wrapper shape. A synthetic manager proves ordering, not provider translation.
5. **Joined transaction/validation:** verify caller-owned commit lies outside the facade, and overlapping validation translation is not applied twice.
6. **Module verification:** public contract accessible, internals not imported by callers.
7. **HTTP boundary:** assert the serialized object has exactly code/message, appropriate statuses, and no cause, stack trace, or technical message. Verify one server-side diagnostic log event retaining the cause; test unknown-failure fallback.

Read [EXAMPLES.md](EXAMPLES.md) and [TESTING.md](TESTING.md) for test snippets. State whether tests were actually executed in a consuming application or only supplied as instructional examples.

## 7. State Execution Limits and Hand Off HTTP Mapping

Proxy-based AOP requires calls through Spring proxies. Self-invocation bypasses advice; JDK proxies expose interface methods; class proxies cannot intercept private/final methods or proxy final classes. Kotlin targets need an appropriate open-class strategy, such as the project's Spring all-open setup.

Synchronous advice does not catch failures emitted after a reactive subscription or async task starts. Use the corresponding reactive/completion handling at that execution boundary; do not block in an aspect to turn it into a synchronous recipe.

At the web handling boundary, log `DomainException.getCause()` server-side (or the wrapper when cause is null) and return a freshly constructed `ErrorDto(code, message)`. Do not return/serialize the exception. Unknown technical failures remain unchanged at the aspect and receive a generic safe DTO from the HTTP fallback. Avoid logging in both the aspect and handler, and apply the server's diagnostic-log redaction/access controls.

Keep HTTP status decisions out of `DomainException` and the module translator. This example intentionally uses a plain two-field DTO, not ProblemDetail; see [HTTP-ERRORS.md](HTTP-ERRORS.md). Use [spring-boot-web-api](../spring-boot-web-api/SKILL.md) for general MVC wiring and adapt framework-specific error handlers to the chosen DTO/status/header policy rather than replacing every framework error with a 500.

## Official References

- [Boot 4 AOP starter rename](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide#aop-starter-pom)
- [Boot 4 AOP auto-configuration](https://docs.spring.io/spring-boot/4.0/reference/features/aop.html)
- [Spring proxy mechanics](https://docs.spring.io/spring-framework/reference/core/aop/proxying.html)
- [Pointcut semantics](https://docs.spring.io/spring-framework/reference/core/aop/ataspectj/pointcuts.html)
- [Advice ordering](https://docs.spring.io/spring-framework/reference/core/aop/ataspectj/advice.html#aop-ataspectj-advice-ordering)
- [Transaction annotations and ordering](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html)
- [Transaction propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)
- [Method validation processor](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/validation/beanvalidation/MethodValidationPostProcessor.html)
- [Transaction manager extension points](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/support/AbstractPlatformTransactionManager.html)
- [Hibernate constraint metadata](https://docs.hibernate.org/orm/7.1/javadocs/org/hibernate/exception/ConstraintViolationException.html)
- [Spring Modulith fundamentals](https://docs.spring.io/spring-modulith/reference/fundamentals.html)
