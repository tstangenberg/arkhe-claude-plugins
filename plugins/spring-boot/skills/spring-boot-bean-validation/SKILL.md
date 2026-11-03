---
name: spring-boot-bean-validation
description: Bean Validation 3.1 implementation for Spring Boot 4. Use when adding @NotNull, @NotBlank, @Size, @Valid, or other Jakarta constraints, writing custom ConstraintValidator classes, validating service-layer methods with @Validated, translating ConstraintViolationException into domain exceptions with an aspect, mapping MethodArgumentNotValidException or HandlerMethodValidationException or ConstraintViolationException to HTTP responses, or testing validation rules. Covers Hibernate Validator, constraint groups, cascaded validation, record DTOs, and dependency-injected validators.
spring-boot-version: "4.0"
---

# Bean Validation for Spring Boot 4

Declarative input validation with Jakarta Bean Validation 3.1 (Hibernate Validator as the implementation), applied at the controller boundary, the service layer, and in custom constraints.

## Scope

| Topic | This skill | Other skill |
|-------|-----------|-------------|
| Constraint annotations, custom validators, method validation, exception mapping | Yes | - |
| Service-layer validation with an aspect that translates violations into domain exceptions | Yes | - |
| Controller wiring (`@RequestBody`, DTO shape, ProblemDetail setup) | Summary only | `spring-boot-web-api` |
| Validator and exception tests (`@WebMvcTest`, plain unit tests) | Summary only | `spring-boot-testing` |

## Core Workflow

1. Add constraints to DTOs or domain value types → 2. Trigger validation (`@Valid`, `@Validated`) → 3. Write custom validators when built-ins are not enough → 4. Map violations to HTTP responses → 5. Test the rules

See [WORKFLOW.md](WORKFLOW.md) for detailed step-by-step instructions with code examples.

## Quick Reference

| Need | Use |
|------|-----|
| Validate a `@RequestBody` | `@Valid` on the parameter |
| Validate query/path params | `@Validated` on the controller class, constraints on the parameters |
| Validate a service method | `@Validated` on the service class, constraints on parameters |
| Translate service violations | One `@Order(HIGHEST_PRECEDENCE)` aspect, not try/catch per method |
| Validate nested objects | `@Valid` on the field, or `List<@Valid Item>` for elements |
| Different rules per operation | Groups: `@Validated(OnCreate.class)` |
| Custom rule that needs a bean | `ConstraintValidator` as a Spring bean (constructor injection works) |

See [EXAMPLES.md](EXAMPLES.md) for complete working examples including:
- **Request records** with built-in and nested constraints
- **Method validation** on a service layer
- **Custom constraint** with an injected dependency
- **Exception mapping** to ProblemDetail for all three validation exception types

## Spring Boot 4 Specifics

- **Bean Validation 3.1** (`jakarta.validation.*`), implemented by Hibernate Validator
- **`HandlerMethodValidationException`** is the 400 path for constraints on controller method parameters, without `@Valid` on a `@RequestBody`
- **`MethodArgumentNotValidException`** is the 400 path for `@Valid @RequestBody`; `@Valid @ModelAttribute` raises `BindException` instead
- **`ConstraintViolationException`** from `@Validated` service beans is **not** mapped to 400 by default; translate it in a service-layer aspect into a domain exception, which the web layer then maps
- **Spring-injected validators**: `ConstraintValidator` implementations are created by Spring, so constructor injection works without extra setup

## Critical Reminders

1. **Constrain at the boundary, enforce invariants in the domain** — annotations validate input shape; aggregates still guard their own invariants
2. **`@Valid` cascades, constraints don't** — a constraint on a nested object does nothing until `@Valid` is placed on the field or element
3. **Method validation needs a proxy** — self-invocation and `final` classes skip it
4. **Translate in one place** — a service-layer aspect converts `ConstraintViolationException` to a domain exception; without it, a bad service call becomes a 500
5. **Keep validators side-effect free** — `isValid` may run many times and in any order

## Detailed References

- **Workflow**: See [WORKFLOW.md](WORKFLOW.md) for step-by-step implementation
- **Examples**: See [EXAMPLES.md](EXAMPLES.md) for complete working code
- **Troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues

## Related Skills

| Need | Skill |
|------|-------|
| Controllers, ProblemDetail, request DTOs | `spring-boot-web-api` |
| Testing validation rules | `spring-boot-testing` |
| Proxy mechanics, advice ordering, general exception translation | [spring-boot-aop](../spring-boot-aop/SKILL.md) |
| Aggregate invariants | `domain-driven-design` |
| Dependency versions | `spring-boot-verify` |

## Anti-Pattern Checklist

| Anti-Pattern | Fix |
|--------------|-----|
| `@Valid` missing on nested DTO | Add `@Valid` to the field or element type |
| try/catch for `ConstraintViolationException` in each service method | One `@Order(HIGHEST_PRECEDENCE)` aspect translates for all `@Validated` beans |
| Domain code throwing `ConstraintViolationException` to the web layer | Translate in the service aspect; web advice handles only the domain exception |
| Validator queries the DB with side effects | Keep reads only; put writes in the application service |
| Same DTO for create and update with `@Null`/`@NotNull` clash | Use validation groups or separate request types |
| Hard-coded English messages | Use message keys in `ValidationMessages.properties` or `messages.properties` |
| Calling a `@Validated` method from inside its own class | Move the call through the proxy, or split the class |
