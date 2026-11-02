# Log the Cause, Return Only Code and Message

## Boundary Contract

The module translator produces the single `DomainException(code, message, cause)` from [EXAMPLES.md](EXAMPLES.md). In-process Java callers receive that exception, including its diagnostic cause. **HTTP callers receive only `ErrorDto(code, message)`**. Do not serialize a `Throwable`, even when its top-level message is safe.

The handler owns HTTP status selection and server-side logging. The translator/aspect must not log and rethrow the same failure: logging once at the handling boundary avoids duplicate stack traces. For a non-HTTP entry point, place equivalent logging at the message/job handling boundary instead.

This example intentionally uses a plain DTO, **not ProblemDetail**. General Spring MVC wiring belongs to `spring-boot-web-api`; its ProblemDetail recipes are not the response contract for this example.

## Response DTO

Place the web types in `com.example.customer.web`, internal to the customer module. Each public type has its own file. `ErrorDto.java`:

```java
package com.example.customer.web;

public record ErrorDto(String code, String message) {}
```

The DTO has no cause, stack trace, technical details, or exception-class field. Keep safe messages curated by the translator; never populate them from an unknown technical exception's `getMessage()`.

## Exception Handler

`CustomerErrorHandler.java`:

```java
package com.example.customer.web;

import com.example.customer.DomainException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(basePackages = "com.example.customer.web")
public class CustomerErrorHandler {
    private static final Logger log = LoggerFactory.getLogger(CustomerErrorHandler.class);

    @ExceptionHandler(DomainException.class)
    public ResponseEntity<ErrorDto> handleDomain(DomainException exception) {
        // Throwable as the final SLF4J argument logs the cause's stack trace.
        // A business error without a cause still has useful wrapper diagnostics.
        Throwable diagnostic = exception.getCause() != null
            ? exception.getCause() : exception;
        log.error("Customer request failed; code={}", exception.getCode(), diagnostic);

        return ResponseEntity.status(statusFor(exception.getCode()))
            .body(new ErrorDto(exception.getCode(), exception.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorDto> handleUnexpected(Exception exception) {
        log.error("Unexpected customer request failure", exception);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorDto("INTERNAL_ERROR", "An unexpected error occurred"));
    }

    private HttpStatus statusFor(String code) {
        return switch (code) {
            case "CUSTOMER_ALREADY_EXISTS", "CUSTOMER_CONCURRENT_MODIFICATION" ->
                HttpStatus.CONFLICT;
            case "CUSTOMER_VERIFICATION_UNAVAILABLE" -> HttpStatus.SERVICE_UNAVAILABLE;
            default -> HttpStatus.INTERNAL_SERVER_ERROR;
        };
    }
}
```

Status belongs here, not in `DomainException`. Different error codes can share the same Java class while mapping to different statuses. An unrecognized domain code retains its safe code/message but gets status 500. An unknown **technical exception** gets the generic DTO; its diagnostic message is logged, not returned.

The catch-all is an application-failure fallback, not a complete Spring MVC error policy. In a real application, register specific handling for framework request failures (validation, unreadable JSON, unsupported methods, `ErrorResponseException`, and similar) before that fallback, preserving their appropriate status and headers and constructing the same two-field DTO. Existing `ResponseEntityExceptionHandler`/ProblemDetail advice must be adapted or scoped deliberately so it neither competes with this handler nor gets turned into a generic 500 by the fallback. Security-filter failures run outside controller advice and need a matching response policy in security handlers. Do not claim the two-field contract for these paths until they are configured and tested.

Logs contain technical diagnostics that may include SQL, provider messages, or sensitive values. Keep them in access-controlled server logs with the application's redaction/retention policy; do not route them into client responses or user-visible telemetry. Do not log entire request bodies or credentials alongside the failure. The example uses error-level logging for clarity; severity can be adjusted for expected business conflicts without exposing the cause.

## HTTP Response Tests

Use Spring MVC Test, JUnit Jupiter, Hamcrest, and JSON support from the consuming application. This class tests the handler through HTTP serialization; it is separate from the proxy/transaction tests in [TESTING.md](TESTING.md).

```java
package com.example.customer.web;

import com.example.customer.DomainException;
import java.sql.SQLException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import static org.hamcrest.Matchers.aMapWithSize;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class CustomerErrorHandlerTest {
    private MockMvc mvc;

    @BeforeEach
    void setup() {
        mvc = MockMvcBuilders.standaloneSetup(new FailingController())
            .setControllerAdvice(new CustomerErrorHandler())
            .build();
    }

    @Test
    void returnsOnlySafeDomainCodeAndMessage() throws Exception {
        mvc.perform(get("/test/domain"))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$", aMapWithSize(2)))
            .andExpect(jsonPath("$.code").value("CUSTOMER_ALREADY_EXISTS"))
            .andExpect(jsonPath("$.message")
                .value("A customer with this email already exists"))
            .andExpect(jsonPath("$.cause").doesNotExist())
            .andExpect(jsonPath("$.stackTrace").doesNotExist())
            .andExpect(content().string(not(containsString("sensitive diagnostic"))));
    }

    @Test
    void returnsGenericDtoForAnUnknownTechnicalFailure() throws Exception {
        mvc.perform(get("/test/unexpected"))
            .andExpect(status().isInternalServerError())
            .andExpect(jsonPath("$", aMapWithSize(2)))
            .andExpect(jsonPath("$.code").value("INTERNAL_ERROR"))
            .andExpect(jsonPath("$.message").value("An unexpected error occurred"))
            .andExpect(content().string(not(containsString("sensitive diagnostic"))));
    }

    @RestController
    static class FailingController {
        @GetMapping("/test/domain")
        public void domainFailure() {
            throw new DomainException("CUSTOMER_ALREADY_EXISTS",
                "A customer with this email already exists",
                new SQLException("sensitive diagnostic"));
        }

        @GetMapping("/test/unexpected")
        public void unexpectedFailure() {
            throw new IllegalStateException("sensitive diagnostic");
        }
    }
}
```

Also assert 409 for concurrent modification, 503 for verification unavailability, and 500 for an unknown domain code. Test adapted framework and security error paths separately.

### Verify Cause Logging

If the consuming application uses Logback (Boot's default logging backend), add this separate JUnit test in `com.example.customer.web`. It verifies one diagnostic event and cause identity, not merely a message containing the cause's text. Apply the same check to `handleUnexpected` and to a domain error with a null cause (where the wrapper is logged).

```java
@Test
void logsTheOriginalCauseOnceAndKeepsItOutOfTheDto() {
    var logger = (ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory
        .getLogger(CustomerErrorHandler.class);
    var appender = new ch.qos.logback.core.read.ListAppender<
        ch.qos.logback.classic.spi.ILoggingEvent>();
    var previousLevel = logger.getLevel();
    appender.start();
    logger.setLevel(ch.qos.logback.classic.Level.ERROR);
    logger.addAppender(appender);
    try {
        var cause = new java.sql.SQLException("sensitive diagnostic");
        var failure = new DomainException("CUSTOMER_ALREADY_EXISTS",
            "A customer with this email already exists", cause);

        var response = new CustomerErrorHandler().handleDomain(failure);

        org.assertj.core.api.Assertions.assertThat(appender.list).hasSize(1);
        var diagnostic = (ch.qos.logback.classic.spi.ThrowableProxy)
            appender.list.get(0).getThrowableProxy();
        org.assertj.core.api.Assertions.assertThat(diagnostic.getThrowable())
            .isSameAs(cause);
        org.assertj.core.api.Assertions.assertThat(response.getBody())
            .isEqualTo(new ErrorDto("CUSTOMER_ALREADY_EXISTS",
                "A customer with this email already exists"));
    } finally {
        logger.detachAppender(appender);
        logger.setLevel(previousLevel);
        appender.stop();
    }
}
```

Use imports for JUnit's `Test` and the example's `DomainException`. Adapt capture to the application's backend if it is not Logback; don't add a competing logging backend just for this test. Run logger-mutating tests without parallel access to the same logger.

These snippets are instructional. Do not report them as executed tests unless run in an actual consuming application/build fixture.
