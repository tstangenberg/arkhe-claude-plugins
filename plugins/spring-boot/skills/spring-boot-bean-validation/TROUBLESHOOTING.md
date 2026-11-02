# Bean Validation Troubleshooting

## Common Issues

### Issue: Nested Constraints Are Ignored

**Symptom**: `@NotBlank` on a field of a nested DTO never fails.

**Cause**: Constraints cascade only through `@Valid`. The parent type is validated, but the child is not traversed.

**Fix**:
```java
public record CreateOrderRequest(
    @NotNull Long customerId,
    @Valid @NotNull ShippingAddress address   // @Valid cascades into ShippingAddress
) {}
```

### Issue: Query Parameter Constraints Do Nothing

**Symptom**: `@Min(1) @RequestParam int page` accepts `0`.

**Cause**: The controller class lacks `@Validated`. Spring only creates the method-validation proxy for annotated classes.

**Fix**: Add `@Validated` at the class level.

### Issue: Service Method Validation Is Skipped

**Symptom**: `@Validated` on a service class, but invalid arguments reach the method body.

**Causes** (in order of likelihood):
1. **Self-invocation**: `this.place(...)` inside the same class bypasses the proxy. Inject the bean into itself, or move the method to another bean.
2. **Missing `@Validated`** on the class. `@Valid` on a parameter alone is not enough.
3. **`final` class or method**: The proxy cannot override it, so no validation runs and no error is shown.
4. **Bean not proxied**: Spring creates the proxy only for beans it manages. `new OrderService(...)` in a test bypasses it.

### Issue: Wrong HTTP Status for Validation Failure

**Symptom**: A bad request returns 500, or a 400 without the field details.

**Cause**: The `ConstraintViolationException` from a `@Validated` service is not translated. Spring has no default 400 for it.

**Fix**: Add the translation aspect. See [EXAMPLES.md](EXAMPLES.md#service-layer-translation). If the aspect is present and the 500 persists, check that its pointcut matches the bean. A `final` class or a bean not created by Spring is not proxied, so the aspect never runs.

### Issue: Custom Validator Fails to Inject Dependencies

**Symptom**: `NullPointerException` on a repository field inside `isValid`, or `NoSuchBeanDefinitionException` at startup.

**Causes**:
1. The validator is instantiated with `new` somewhere, for example in a test. Spring only injects validators it creates, so a hand-built instance has null fields. Use the Spring context or inject a stub.
2. The validator is not a bean and has no matching constructor for Spring to use. Make it a `@Component` with a single constructor.

### Issue: Message Key Shows Literally

**Symptom**: The API returns `{validation.email.duplicate}` instead of the text.

**Cause**: The key is not found in `ValidationMessages.properties` or `messages.properties` on the classpath, or the file name is wrong.

**Fix**: Confirm the file is in `src/main/resources` and the key matches exactly, including dots.

### Issue: Two Errors for One Missing Field

**Symptom**: A null `email` produces both "must not be null" and a custom-constraint message such as "Email is already registered".

**Cause**: The custom validator returned `false` for `null`. Built-in constraints such as `@Email` treat `null` as valid, so only `@NotNull` or `@NotBlank` reports it.

**Fix**: Return `true` for `null` in custom validators, and let `@NotNull` or `@NotBlank` own the null case.

### Issue: Group Constraints Run on the Wrong Path

**Symptom**: A `@NotBlank(groups = OnCreate.class)` field is checked on update too.

**Cause**: `@Valid` runs the default group only. A group runs only when the trigger is `@Validated(OnCreate.class)`, and then only that group's constraints run.

**Fix**: Use `@Validated(OnCreate.class)` on the create endpoint and `@Validated(OnUpdate.class)` on update. Make each group `extends Default` so unannotated constraints still run.

## Spring Boot 4 Notes

### Hibernate Validator Version

Spring Boot manages the Hibernate Validator version through its dependency BOM. Check the version the project resolves:

```bash
./mvnw dependency:tree -Dincludes=org.hibernate.validator
```

If a project pins an older Hibernate Validator, the `jakarta.validation` API may load from one version and the implementation from another. The symptom is an `AbstractMethodError` or a `ValidationException` at startup.

### Missing `spring-boot-starter-validation`

`spring-boot-starter-web` does not bring Hibernate Validator in transitively, so the dependency must be declared explicitly. If constraints appear to do nothing and there is no error, check the dependency:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
</dependency>
```

Without an implementation on the classpath, `Validation.buildDefaultValidatorFactory()` fails. With the API jar alone, annotations exist but nothing checks them.
