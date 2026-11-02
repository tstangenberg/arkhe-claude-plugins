# Bean Validation Examples

Complete working examples for Bean Validation 3.1 on Spring Boot 4.

## Request Records

Records keep constraints next to the data. `@Valid` on a collection validates each element.

```java
public record CreateOrderRequest(
    @NotNull Long customerId,
    @NotEmpty List<@Valid OrderLineRequest> items,
    @Size(max = 500) String notes,
    @Email String contactEmail
) {}

public record OrderLineRequest(
    @NotNull Long productId,
    @Positive int quantity,
    @PositiveOrZero BigDecimal unitPrice
) {}
```

```java
@RestController
@RequestMapping("/orders")
class OrderController {

    private final OrderService orders;

    OrderController(OrderService orders) {
        this.orders = orders;
    }

    @PostMapping
    ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrderRequest request) {
        var order = orders.place(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(OrderResponse.from(order));
    }
}
```

**Key points**:
- `@Valid` on `items` is what runs `OrderLineRequest` constraints. Without it they are silently skipped.
- `@Positive` rejects zero. Use `@PositiveOrZero` for prices that may be free.

## Query Parameter Validation

```java
@Validated
@RestController
@RequestMapping("/products")
class CatalogController {

    private final CatalogService catalog;

    CatalogController(CatalogService catalog) {
        this.catalog = catalog;
    }

    @GetMapping
    List<ProductResponse> search(
            @RequestParam @Size(min = 2, max = 100) String q,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Range(min = 1, max = 100) int size) {
        return catalog.search(q, page, size).stream().map(ProductResponse::from).toList();
    }
}
```

**Key points**:
- Class-level `@Validated` is required for parameter constraints to run.
- Violations raise `HandlerMethodValidationException`, not `MethodArgumentNotValidException`.
- `@Range` is a Hibernate Validator constraint, not part of Jakarta Validation. Use `@Min` and `@Max` together if you need portability.

## Service-Layer Method Validation

```java
public record CreateOrderCommand(
    @NotNull Long customerId,
    @NotEmpty List<@Valid OrderLine> lines
) {}

@Validated
@Service
class OrderService {

    private final OrderRepository orders;

    OrderService(OrderRepository orders) {
        this.orders = orders;
    }

    public Order place(@Valid CreateOrderCommand command) {
        // Invariants inside Order still guard the aggregate
        return orders.save(Order.place(command.customerId(), command.lines()));
    }
}
```

**Key points**:
- Method validation runs through the Spring proxy, so the caller must hold a reference to the bean.
- Calling `this.place(...)` from another method in `OrderService` skips validation.
- A `final` class or `final` method cannot be proxied, so validation is skipped silently.

## Custom Constraint with an Injected Dependency

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

@Component
class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {

    private final UserRepository users;

    UniqueEmailValidator(UserRepository users) {
        this.users = users;
    }

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        return email == null || !users.existsByEmail(email);
    }
}
```

```properties
# src/main/resources/ValidationMessages.properties
validation.email.duplicate=Email is already registered
```

```java
public record RegisterUserRequest(
    @NotBlank String name,
    @NotBlank @Email @UniqueEmail String email
) {}
```

**Key points**:
- The validator is a Spring bean, so constructor injection works.
- A `null` value returns `true` so `@NotBlank` alone reports the missing field, with one error instead of two.
- `isValid` reads the database and must not write to it.

## Groups for Create and Update

```java
public interface OnCreate extends Default {}
public interface OnUpdate extends Default {}

public record UserRequest(
    @Null(groups = OnCreate.class)
    @NotNull(groups = OnUpdate.class) Long id,
    @NotBlank String name,
    @NotBlank(groups = OnCreate.class) String password
) {}

@RestController
@RequestMapping("/users")
class UserController {

    @PostMapping
    void create(@Validated(OnCreate.class) @RequestBody UserRequest request) { ... }

    @PutMapping("/{id}")
    void update(@PathVariable Long id, @Validated(OnUpdate.class) @RequestBody UserRequest request) { ... }
}
```

**Key points**:
- `@Validated(OnCreate.class)` runs only the constraints in `OnCreate`. Because `OnCreate extends Default`, the unannotated constraints run too.
- Without `extends Default`, `@NotBlank String name` would be skipped on create. This is the most common group mistake.

## Service-Layer Translation

Service violations are translated once, in an aspect at the highest precedence. Callers, including the web layer, see a domain exception instead of the Jakarta one.

```java
import jakarta.validation.ConstraintViolation;
import jakarta.validation.ConstraintViolationException;
import java.util.Set;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

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
            throw new InvalidInputException("Input is invalid", exception.getConstraintViolations(), exception);
        }
    }
}

// Domain exception: carries the violations so the web layer can report every field
class InvalidInputException extends RuntimeException {

    private final Set<ConstraintViolation<?>> violations;

    InvalidInputException(String message, Set<ConstraintViolation<?>> violations, Throwable cause) {
        super(message, cause);
        this.violations = Set.copyOf(violations);
    }

    Set<ConstraintViolation<?>> getViolations() {
        return violations;
    }
}
```

**Key points**:
- Pointcut on `@within(Validated)` covers every `@Validated` service. Narrow it to a package if needed.
- `HIGHEST_PRECEDENCE` makes sure other advice sees the domain exception.
- The exception keeps the original `ConstraintViolationException` as its cause. Its `toString()` can include invalid values, so do not log whole violations; log the property path and message only.
- The web advice builds the field errors from the violations, using the leaf of each property path (`place.command.customerId` becomes `customerId`) and the message. Parameter-level violations have no property node, so use the parameter name.
- The web advice maps `InvalidInputException` to a 400 ProblemDetail, following the ProblemDetail shape in `spring-boot-web-api`.
- **If the domain model must stay dependency-free**, do not hold `ConstraintViolation` in the domain exception. Have the aspect copy each violation's path leaf and message into a plain record (for example `FieldViolation(String field, String message)`) and pass a `List<FieldViolation>` instead. The domain package then imports nothing from `jakarta.validation`.

**Web-layer requests** still use `@Valid @RequestBody`, which `ResponseEntityExceptionHandler` maps to 400 without any extra code.

## Testing a Constraint Directly

```java
class CreateOrderRequestTest {

    private static final Validator validator =
        Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    void rejectsEmptyItems() {
        var request = new CreateOrderRequest(1L, List.of(), null, null);

        assertThat(validator.validate(request))
            .extracting(v -> v.getPropertyPath().toString())
            .containsExactly("items");
    }

    @Test
    void acceptsValidRequest() {
        var request = new CreateOrderRequest(1L,
            List.of(new OrderLineRequest(10L, 2, BigDecimal.TEN)), "gift", "a@b.ch");

        assertThat(validator.validate(request)).isEmpty();
    }
}
```

**Key points**:
- Build the `Validator` once per class. Building it per test is slow.
- This test needs no Spring context and runs in milliseconds.
- Test the HTTP mapping separately with `@WebMvcTest` (see `spring-boot-testing`).
