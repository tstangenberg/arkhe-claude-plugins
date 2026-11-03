# Bean Validation Workflow

Step-by-step implementation of Bean Validation 3.1 in a Spring Boot 4 application.

## Step 1: Constrain Input Types

Put constraints on the types that receive input: request DTOs, command objects, and value types. Records keep the constraints next to the data.

```java
public record CreateOrderRequest(
    @NotNull Long customerId,
    @NotEmpty List<@Valid OrderLineRequest> items,
    @Size(max = 500) String notes
) {}

public record OrderLineRequest(
    @NotNull Long productId,
    @Positive int quantity,
    @PositiveOrZero BigDecimal unitPrice
) {}
```

**Note**: `@Valid` on `items` cascades into each element. Without it, `OrderLineRequest` constraints are silently skipped.

### Choosing the Constraint

| Input | Constraint |
|-------|-----------|
| Required object reference | `@NotNull` |
| Required string with content | `@NotBlank` (rejects null, empty, and whitespace) |
| Required collection with content | `@NotEmpty` |
| Bounded text or collection | `@Size(min, max)` |
| Numeric range | `@Positive`, `@PositiveOrZero`, `@Min`, `@Max`, `@DecimalMin` |
| Format | `@Email`, `@Pattern(regexp = ...)` |
| Temporal | `@Past`, `@Future`, `@PastOrPresent` |

## Step 2: Trigger Validation

Pick the trigger that matches where the input enters.

### 2a. Request Body

```java
@PostMapping("/orders")
ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrderRequest request) { ... }
```

Failures raise `MethodArgumentNotValidException`.

### 2b. Query and Path Parameters

Constraints on simple parameters need the class-level `@Validated` marker. Without it, Spring does not validate them.

```java
@Validated
@RestController
class CatalogController {

    @GetMapping("/products")
    List<ProductResponse> search(@RequestParam @Size(min = 2) String q,
                                 @RequestParam @Min(0) int page) { ... }
}
```

Failures raise `HandlerMethodValidationException` in Spring 6.1+.

### 2c. Service Methods

Use method validation when the same rules must hold for callers other than HTTP.

```java
@Validated
@Service
class OrderService {

    public Order place(@Valid CreateOrderCommand command) { ... }
}
```

Spring creates an AOP proxy for `@Validated` beans. Failures raise `ConstraintViolationException`.

**Warning**: Calls from inside the same class bypass the proxy. Move the call through the bean, or split the class.

**Keep the raw exception out of callers.** The service validates, but the web layer should not know about Jakarta. Translate it in Step 5a.

## Step 3: Add Custom Constraints When Needed

Write a custom constraint when the rule needs a repository, a clock, or other configuration that a built-in cannot express.

### 3a. Annotation

```java
@Documented
@Constraint(validatedBy = UniqueEmailValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT})
@Retention(RetentionPolicy.RUNTIME)
public @interface UniqueEmail {
    String message() default "{validation.email.duplicate}";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

Use a message key (`{validation.email.duplicate}`), not literal English text. The key is resolved from `ValidationMessages.properties` or `messages.properties`.

### 3b. Validator as a Spring Bean

```java
@Component
class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {

    private final UserRepository users;

    UniqueEmailValidator(UserRepository users) {
        this.users = users;
    }

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        if (email == null) {
            return true; // null is for @NotNull to reject
        }
        return !users.existsByEmail(email);
    }
}
```

Spring creates validators through its bean factory, so constructor injection works. Return `true` for `null` so a rule is checked once: `@NotNull` owns the null case.

**Warning**: The validator is called on every validation. Keep it to reads. Do not write, send mail, or call external services from `isValid`.

## Step 4: Use Groups for Different Operations

Groups let one type serve create and update with different rules.

```java
// Extending Default keeps unannotated constraints (like @NotBlank name) in the create and update paths
public interface OnCreate extends Default {}
public interface OnUpdate extends Default {}

public record UserRequest(
    @Null(groups = OnCreate.class)
    @NotNull(groups = OnUpdate.class) Long id,
    @NotBlank String name,
    @NotBlank(groups = OnCreate.class) String password
) {}
```

**Note**: One field can carry constraints from several groups, as `id` does here. Groups are simplest when the rules differ by only one or two fields. When create and update diverge a lot, use separate request types instead.

```java
@PostMapping("/users")
void create(@Validated(OnCreate.class) @RequestBody UserRequest request) { ... }

@PutMapping("/users/{id}")
void update(@Validated(OnUpdate.class) @RequestBody UserRequest request) { ... }
```

`@Validated(group)` replaces `@Valid` for that parameter. It runs only the constraints in the named group. Unannotated constraints belong to `Default`, so they are skipped unless the group extends `Default`, as above.

## Step 5: Translate Violations

Each trigger produces its own exception, and they belong to different layers. Translate service-layer violations once, in the service layer. Let the web layer handle request-level violations.

| Exception | Raised by | Layer | Default HTTP | Action |
|-----------|-----------|-------|-------------|--------|
| `ConstraintViolationException` | `@Validated` service methods | Service | 500 | **Translate** to a domain exception (5a) |
| `MethodArgumentNotValidException` | `@Valid @RequestBody` | Web | 400 | Covered by `ResponseEntityExceptionHandler` |
| `HandlerMethodValidationException` | Constraints on controller parameters | Web | 400 | Covered by `ResponseEntityExceptionHandler` |

### 5a. Translate Service Violations with an Aspect

Write one aspect that wraps every `@Validated` service. It catches `ConstraintViolationException` and throws a domain exception with a code and field, so no service method needs its own try/catch.

```java
@Aspect
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class ValidationTranslationAspect {

    @Around("@within(org.springframework.validation.annotation.Validated)")
    Object translate(ProceedingJoinPoint joinPoint) throws Throwable {
        try {
            return joinPoint.proceed();
        }
        catch (ConstraintViolationException exception) {
            throw new InvalidInputException("Input is invalid", exception.getConstraintViolations(), exception); // see EXAMPLES.md
        }
    }
}
```

**Why an aspect**: The translation applies to every `@Validated` bean, including ones added later. A per-method try/catch is easy to forget, and then the raw exception leaks.

**Why `HIGHEST_PRECEDENCE`**: Low-order around advice surrounds higher-order advice and can translate failures before returning to the caller. Inner advice can still see the original failure; this does not guarantee that every other aspect sees the domain exception.

**Coexisting aspects**: Do not give overlapping translators equal order values and assume a relative order. Let this aspect own validation mapping; a general facade translator must pass the resulting exception through unchanged. Verify method-validation and transaction advisor chains through Spring beans. See [spring-boot-aop](../spring-boot-aop/SKILL.md) for ordering and facade exception translation.

**Pointcut scope**: `@within(Validated)` matches the class annotation. Narrow it to your service package if the aspect should not touch other beans.

**Output**: Service violations reach the web layer as a domain exception. The web advice maps it to 400 with a ProblemDetail that names the offending fields.

## Step 6: Test the Rules

Test constraints directly with a `Validator` for fast feedback. Test the wiring with a slice test.

```java
class CreateOrderRequestTest {

    private static final Validator validator =
        Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    void rejectsEmptyItems() {
        var request = new CreateOrderRequest(1L, List.of(), null);

        assertThat(validator.validate(request))
            .extracting(v -> v.getPropertyPath().toString())
            .containsExactly("items");
    }
}
```

For the HTTP mapping, use `@WebMvcTest` as described in `spring-boot-testing`. Assert the status is 400 and the ProblemDetail body names the field.

**Output**: Validation rules covered by fast unit tests, plus one HTTP test per exception type.
