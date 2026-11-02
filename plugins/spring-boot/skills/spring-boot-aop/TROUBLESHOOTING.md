# Spring AOP Troubleshooting

## Advice Never Runs

Check these in order:

1. Confirm the target and `@Aspect` are Spring beans and AOP auto-configuration is active.
2. Inspect the exact pointcut against the actual bean's package, type, and public method. A class-name/package convention is not an annotation contract.
3. Call the injected Spring bean, not an object created with `new`.
4. Inspect `AopUtils.isAopProxy(bean)` and whether it is a JDK or class-based proxy.
5. Check for self-invocation: `this.register()` bypasses the proxy, even if `register()` is annotated.
6. With JDK proxies, inject an interface and expose the intended methods on it. With class proxies, remove `final` from advised methods/classes; private methods are not interceptable.

Move an internally invoked boundary to another bean if appropriate. Do not enable AspectJ weaving or use `AopContext.currentProxy()` merely to avoid designing an explicit boundary.

## Pointcut Matches Too Much

An application-wide `execution(* *(..))` or every `@Service` can translate a failure in the wrong module, advise translator beans, or map the same failure repeatedly.

Use one public facade type or a module-specific opt-in annotation combined with a module package restriction. Keep aspects and translators out of the matched target set. Annotation placement and `@within` versus `@annotation` matter; see [WORKFLOW.md](WORKFLOW.md).

## Commit-Time Exception Escapes Translation

Inspect both **advisor order** and **transaction ownership**:

- The translator must surround transaction advice, not execute inside it.
- The target invocation must complete the transaction. Joining a caller's transaction defers final commit until after the aspect has returned.
- A test annotated `@Transactional` can hide this problem by supplying the outer transaction and rolling it back rather than committing.
- A commit failure may have a transaction wrapper type rather than `DataAccessException`. Translate a known wrapper only with an explicit policy and tested cause shape; do not map every nested integrity exception automatically.

Do not prescribe `REQUIRES_NEW`, force an early flush, or swallow a rollback-only failure merely to make a test pass. Each changes transaction semantics or hides the real failure.

## Validation or Another Aspect Sees the Wrong Exception

Lower order values enter earlier and exit later. Inner advice can see the original exception; only callers outside the translator see the replacement.

Do not assign two overlapping aspects `HIGHEST_PRECEDENCE` and depend on an unspecified relative order. Keep validation mapping in its validation aspect, choose distinct orders for overlapping advice, and pass already-translated errors through the outer translator. Inspect the actual `Advised.getAdvisors()` chain; method validation can be supplied by a bean post-processor rather than the same ordered advisor registration path.

If method-validation adaptation is enabled, the failure can be Spring's `MethodValidationException` rather than Jakarta's `ConstraintViolationException`. Coordinate with [spring-boot-bean-validation](../spring-boot-bean-validation/SKILL.md), rather than adding a catch-all business mapping.

## Wrong Business Exception Is Produced

- Match a known constraint identifier from structured provider metadata; SQL message text varies by database, driver, and locale.
- A generic integrity violation can mean a nullability, foreign-key, check, or uniqueness failure. Leave unknown identities unchanged.
- SQLState class `23` indicates an integrity violation, not which business rule failed.
- An optimistic-locking failure is only a meaningful concurrent-change error for the operation and resource the facade actually represents.
- A timeout is an availability failure, not an invalid customer or a failed business invariant.

Test both recognized and unrecognized inputs. Do not return provider messages as public exception messages.

## Failure Is Wrapped Twice

Check the entire call path: repository translation, validation translation, general facade translation, and HTTP mapping. Each owns a different boundary.

Return the original exception when no mapping matches, and short-circuit already-translated module errors. For errors from another module, define an intentional contract adaptation only where needed; do not remap them just because their cause contains a SQL exception. A cause chain is diagnostic information, not proof that the current module owns the error.

## Cause Leaks into an HTTP Response or Is Not Logged

Use a separate `ErrorDto` with exactly `code` and `message`. Return a new DTO, not `DomainException`, its cause, a map built from Throwable properties, or the cause's message. Keep translated messages curated and unknown failures generic. Check the serialized object has exactly two fields.

Log the cause as the final throwable argument to the server logger, once at the handling boundary. If it is null, log the wrapper. String concatenation or `cause.getMessage()` alone loses the stack trace. Avoid duplicate aspect/handler logs and protect diagnostic logs with redaction/access controls. See [HTTP-ERRORS.md](HTTP-ERRORS.md).

A catch-all web handler is not a complete request-error policy. Preserve statuses and headers for framework errors and ensure existing ProblemDetail advice does not compete with the DTO contract; security-filter errors need their own handler.

## Reactive or Async Failure Is Not Caught

A synchronous `try/catch` only covers `proceed()` until it returns or throws. It does not cover an error emitted later by `Mono`/`Flux`, an exceptional future completion, or work started on another thread.

Use the relevant reactive error operator, completion handler, or async exception handler at that execution boundary. Do not block a reactive publisher in the aspect. State which synchronous failures the example handles instead of promising universal interception.

## Unit Test Passes but Application Fails

Direct translator tests verify mapping policy, not pointcuts or ordering. Direct calls to an aspect omit Spring proxy behavior entirely.

Add a Spring-managed proxy test, verify that the target is proxied, and exercise an exception thrown during transaction completion. A synthetic transaction manager can test advice ordering; a real database integration test is still needed to verify the provider's actual exception chain and constraint metadata. See [EXAMPLES.md](EXAMPLES.md).
