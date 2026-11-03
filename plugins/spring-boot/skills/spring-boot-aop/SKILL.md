---
name: spring-boot-aop
description: Implement and review Spring Boot 4 proxy-based AOP. Use when writing @Aspect, @Around, @Pointcut, or facade-boundary aspects; translating SQL, persistence, or external-client exceptions into module/domain exceptions; ordering advice around @Transactional or @Validated; debugging self-invocation or proxy bypass; or testing aspects through Spring proxies. Includes module-owned exception translation for Spring Modulith using one DomainException with code, safe message, and cause; log diagnostics server-side and return only a code/message DTO.
spring-boot-version: "4.0"
---

# Spring Boot AOP

Implement cross-cutting behavior with Spring-managed proxies. Use module-owned exception translation as the worked example; keep interception mechanics separate from business-specific mapping policy.

## Scope

| Topic | Owner |
|-------|-------|
| Advice, pointcuts, proxies, ordering, aspect tests | This skill |
| Technical-to-module exception translation at service facades | Example in this skill |
| Constraints and validation-specific translation | `spring-boot-bean-validation` |
| Cause logging and two-field HTTP error DTO | Boundary example in this skill |
| General controller wiring and framework HTTP errors | `spring-boot-web-api` |
| Module visibility and public contracts | `spring-boot-modulith` |

Do not introduce custom aspects where Spring's built-in transaction, security, caching, or retry facilities already provide the required behavior. AspectJ weaving is distinct from proxy-based AOP and outside this skill's setup scope.

## Core Workflow

1. Inspect the Boot version, existing AOP dependencies, proxies, and advice.
2. Choose the boundary: public facade methods in one module by default.
3. Choose the least powerful advice; use `@Around` when replacing an exception.
4. Keep the aspect small; delegate business mappings to a module-owned translator.
5. Define advice order and identify who completes the transaction.
6. Test through Spring proxies, including successful calls and unmapped failures.

Read [WORKFLOW.md](WORKFLOW.md) before implementation, [EXAMPLES.md](EXAMPLES.md) for the module recipe, [TESTING.md](TESTING.md) for Spring-proxy and commit-order tests, [HTTP-ERRORS.md](HTTP-ERRORS.md) for cause logging and the two-field response, and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) when interception or translation fails.

## Essential Rules

- Match a deliberate facade boundary, not every `@Service` or every method in the application. AspectJ annotations do not themselves enable weaving.
- Invoke `proceed()` exactly once in exception translation; return its successful result unchanged.
- Lower order values surround higher values. An outer aspect sees inner transaction completion only when that invocation completes the transaction. Verify actual advisor chains, not just annotations.
- Proxy calls are required. Self-invocation bypasses advice; class-based proxies cannot advise final/private methods, and JDK proxies expose interface methods.
- Map recognized failures only. Do not equate all integrity violations with duplicates or technical outages with business-rule failures.
- Preserve the original caught failure as the cause. Pass unknown and already-translated exceptions through unchanged; do not catch JVM `Error` types.
- Use one `DomainException(code, message, cause)`, not per-error subclasses. Keep code/message safe and framework-free; store the cause using the exception superclass.
- Log the cause once at the handling boundary. Return only `ErrorDto(code, message)` to HTTP callers; never serialize the exception or return technical messages. Unknown technical failures get a generic safe DTO.
- A synchronous catch does not observe later reactive emissions or async completion failures.

## Output

Produce a scoped aspect, its explicit ordering rationale, a module-owned translator using the single exception contract, plus translator unit tests and Spring-proxy tests. For the HTTP boundary, produce cause logging and a code/message-only DTO with serialization tests. State provider-specific assumptions and transaction/async limitations. When reviewing, report concrete boundary, mapping, or ordering defects rather than proposing blanket AOP adoption.

## Common Issues

| Symptom | Check |
|---------|-------|
| Advice never runs | Bean management, pointcut, proxy type, self-invocation |
| Commit failure escapes | Advice order and caller-owned transaction |
| Wrong domain error | Constraint identity, mapping context, unknown fallback |
| Validation is translated twice | Mapping ownership and deterministic relative order |

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for diagnosis.

## Related Skills

- [Validation](../spring-boot-bean-validation/SKILL.md): constraints and service validation translation.
- [Modulith](../spring-boot-modulith/SKILL.md): module boundaries and named interfaces.
- [Data DDD](../spring-boot-data-ddd/SKILL.md): repositories and transactions.
- [Web API](../spring-boot-web-api/SKILL.md): general MVC wiring and framework errors; this example intentionally returns a plain DTO instead of ProblemDetail.
- [Testing](../spring-boot-testing/SKILL.md): integration test setup.
