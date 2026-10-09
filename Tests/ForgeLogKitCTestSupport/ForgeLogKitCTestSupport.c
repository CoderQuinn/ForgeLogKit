#include "ForgeLogKitCTestSupport.h"
#include <pthread.h>
#include <sched.h>
#include <stdlib.h>

/* Hidden implementation seams from FLLogC.c. They are deliberately absent
 * from the product header and are consumed only by this test-support target. */
unsigned char FLLogCInternalTypeForLevel(FLLogLevel level);
int FLLogCInternalIsPublic(FLLogPrivacy privacy);
int FLLogCInternalFormatMessage(
    char *buf,
    unsigned long size,
    const char *category,
    FLLogLevel level,
    const char *msg
);
int FLLogCInternalVFormatMessage(
    char *buf,
    unsigned long size,
    const char *category,
    FLLogLevel level,
    const char *fmt,
    va_list ap
);
int FLLogCInternalWithHandleBorrow(
    FLLogCHandle h,
    void (*body)(void *),
    void *context
);

static void FLLogCTestLock(pthread_mutex_t *lock) {
    if (pthread_mutex_lock(lock) != 0) abort();
}

static void FLLogCTestUnlock(pthread_mutex_t *lock) {
    if (pthread_mutex_unlock(lock) != 0) abort();
}

static void FLLogCTestBroadcast(pthread_cond_t *condition) {
    if (pthread_cond_broadcast(condition) != 0) abort();
}

static void FLLogCTestWait(
    pthread_cond_t *condition,
    pthread_mutex_t *lock
) {
    if (pthread_cond_wait(condition, lock) != 0) abort();
}

static void FLLogCTestResetEvent(FLLogCTestEvent *event) {
    if (!event) return;
    event->message[0] = '\0';
    event->logType = 0;
    event->isPublic = 0;
}

static void FLLogCTestSetRouting(
    FLLogCTestEvent *event,
    FLLogLevel level,
    FLLogPrivacy privacy
) {
    event->logType = FLLogCInternalTypeForLevel(level);
    event->isPublic = FLLogCInternalIsPublic(privacy);
}

static int FLLogCTestPrepareFormatted(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    FLLogCTestEvent *event,
    const char *fmt,
    ...
) {
    FLLogCTestResetEvent(event);
    if (!event) return 0;

    va_list ap;
    va_start(ap, fmt);
    int result = FLLogCInternalVFormatMessage(
        event->message,
        sizeof(event->message),
        category,
        level,
        fmt,
        ap
    );
    va_end(ap);

    if (result) FLLogCTestSetRouting(event, level, privacy);
    return result;
}

void FLLogCTestFormatted(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, "Value: %d", 42);
    FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "String: %s", "test");
    FLLogCLogfH(h, FL_LOG_LEVEL_WARN, "Float: %.2f", 3.14);
}

void FLLogCTestNullFormat(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, 0);
}

void FLLogCTestPrivateFormatted(FLLogCHandle h) {
    FLLogCLogfPrivacyH(
        h,
        FL_LOG_LEVEL_ERROR,
        FL_LOG_PRIVACY_PRIVATE,
        "error code=%d",
        42
    );
}

void FLLogCTestAllLevels(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "Debug level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, "Info level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_WARN, "Warn level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_ERROR, "Error level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_FAULT, "Fault level test");
}

int FLLogCTestPrepareLiteral(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *message,
    FLLogCTestEvent *event
) {
    FLLogCTestResetEvent(event);
    if (!event) return 0;

    int result = FLLogCInternalFormatMessage(
        event->message,
        sizeof(event->message),
        category,
        level,
        message
    );
    if (result) FLLogCTestSetRouting(event, level, privacy);
    return result;
}

int FLLogCTestPrepareFormattedValues(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    int count,
    const char *name,
    double ratio,
    FLLogCTestEvent *event
) {
    return FLLogCTestPrepareFormatted(
        category,
        level,
        privacy,
        event,
        "count=%d name=%s ratio=%.2f",
        count,
        name,
        ratio
    );
}

int FLLogCTestPrepareSensitiveFormattedValues(
    const char *authorizationValue,
    const char *credentialURL,
    FLLogCTestEvent *event
) {
    return FLLogCTestPrepareFormatted(
        "Redaction",
        FL_LOG_LEVEL_INFO,
        FL_LOG_PRIVACY_PUBLIC,
        event,
        "Authorization: Bearer %s\nendpoint=%s",
        authorizationValue,
        credentialURL
    );
}

int FLLogCTestPrepareOversizedFormattedValue(
    const char *value,
    FLLogCTestEvent *event
) {
    return FLLogCTestPrepareFormatted(
        "Oversized",
        FL_LOG_LEVEL_ERROR,
        FL_LOG_PRIVACY_PUBLIC,
        event,
        "%s",
        value
    );
}

int FLLogCTestPrepareNullFormat(FLLogCTestEvent *event) {
    return FLLogCTestPrepareFormatted(
        "Null",
        FL_LOG_LEVEL_INFO,
        FL_LOG_PRIVACY_PUBLIC,
        event,
        0
    );
}

int FLLogCTestRejectsInvalidLiteralInputs(void) {
    char buffer[FL_LOG_MAX_BUF];
    return
        FLLogCInternalFormatMessage(
            0,
            sizeof(buffer),
            "Invalid",
            FL_LOG_LEVEL_INFO,
            "message"
        ) == 0 &&
        FLLogCInternalFormatMessage(
            buffer,
            0,
            "Invalid",
            FL_LOG_LEVEL_INFO,
            "message"
        ) == 0 &&
        FLLogCInternalFormatMessage(
            buffer,
            sizeof(buffer),
            "Invalid",
            FL_LOG_LEVEL_INFO,
            0
        ) == 0;
}

static int FLLogCTestFormatTinyBuffer(const char *fmt, ...) {
    char buffer[8];
    va_list ap;
    va_start(ap, fmt);
    int result = FLLogCInternalVFormatMessage(
        buffer,
        sizeof(buffer),
        "CategoryTooLarge",
        FL_LOG_LEVEL_INFO,
        fmt,
        ap
    );
    va_end(ap);
    return result;
}

int FLLogCTestRejectsTinyFormattedBuffer(void) {
    return FLLogCTestFormatTinyBuffer("message") == 0;
}

typedef struct {
    FLLogCHandle handle;
    pthread_mutex_t lock;
    pthread_cond_t condition;
    int borrowEntered;
    int exerciseClosing;
    int exercisedClosing;
    int releaseBorrow;
    int borrowResult;
    int closingIsEnabled;
    int destroyReturned;
} FLLogCTestBorrowContext;

static void FLLogCTestExerciseAllHandlePaths(FLLogCHandle handle) {
    FLLogCFields fields = {
        .component = "lifecycle",
        .phase = "teardown",
        .errorCode = 0,
        .correlationID = "stress-1",
    };

    FLLogCInfoH(handle, "lifecycle literal");
    FLLogCLogH(
        handle,
        FL_LOG_LEVEL_ERROR,
        FL_LOG_PRIVACY_PRIVATE,
        "lifecycle explicit"
    );
    (void)FLLogCIsEnabledH(handle, FL_LOG_LEVEL_INFO);
    FLLogCLogStructuredH(
        handle,
        FL_LOG_LEVEL_WARN,
        FL_LOG_PRIVACY_PRIVATE,
        &fields,
        "lifecycle structured"
    );
    FLLogCLogfPrivacyH(
        handle,
        FL_LOG_LEVEL_DEBUG,
        FL_LOG_PRIVACY_PUBLIC,
        "lifecycle printf %d",
        42
    );
}

static void FLLogCTestExerciseAndHoldBorrow(void *rawContext) {
    FLLogCTestBorrowContext *context = rawContext;
    FLLogCTestExerciseAllHandlePaths(context->handle);

    FLLogCTestLock(&context->lock);
    context->borrowEntered = 1;
    FLLogCTestBroadcast(&context->condition);
    while (!context->exerciseClosing) {
        FLLogCTestWait(&context->condition, &context->lock);
    }
    FLLogCTestUnlock(&context->lock);

    context->closingIsEnabled = FLLogCIsEnabledH(
        context->handle,
        FL_LOG_LEVEL_INFO
    );
    FLLogCTestExerciseAllHandlePaths(context->handle);

    FLLogCTestLock(&context->lock);
    context->exercisedClosing = 1;
    FLLogCTestBroadcast(&context->condition);
    while (!context->releaseBorrow) {
        FLLogCTestWait(&context->condition, &context->lock);
    }
    FLLogCTestUnlock(&context->lock);
}

static void *FLLogCTestBorrowThread(void *rawContext) {
    FLLogCTestBorrowContext *context = rawContext;
    context->borrowResult = FLLogCInternalWithHandleBorrow(
        context->handle,
        FLLogCTestExerciseAndHoldBorrow,
        context
    );
    return 0;
}

static void *FLLogCTestDestroyThread(void *rawContext) {
    FLLogCTestBorrowContext *context = rawContext;
    FLLogCDestroy(context->handle);

    FLLogCTestLock(&context->lock);
    context->destroyReturned = 1;
    FLLogCTestBroadcast(&context->condition);
    FLLogCTestUnlock(&context->lock);
    return 0;
}

static void FLLogCTestNoopBorrow(void *context) {
    (void)context;
}

int FLLogCTestDestroyWaitsForBorrowedCalls(void) {
    FLLogCTestBorrowContext context = {0};
    context.handle = FLLogCCreate(
        "com.forgelogkit.tests",
        "BorrowedTeardown"
    );
    if (!context.handle) return 0;
    if (pthread_mutex_init(&context.lock, 0) != 0) {
        FLLogCDestroy(context.handle);
        return 0;
    }
    if (pthread_cond_init(&context.condition, 0) != 0) {
        pthread_mutex_destroy(&context.lock);
        FLLogCDestroy(context.handle);
        return 0;
    }

    pthread_t borrower;
    if (pthread_create(&borrower, 0, FLLogCTestBorrowThread, &context) != 0) {
        pthread_cond_destroy(&context.condition);
        pthread_mutex_destroy(&context.lock);
        FLLogCDestroy(context.handle);
        return 0;
    }

    FLLogCTestLock(&context.lock);
    while (!context.borrowEntered) {
        FLLogCTestWait(&context.condition, &context.lock);
    }
    FLLogCTestUnlock(&context.lock);

    pthread_t destroyer;
    if (pthread_create(&destroyer, 0, FLLogCTestDestroyThread, &context) != 0) {
        FLLogCTestLock(&context.lock);
        context.exerciseClosing = 1;
        context.releaseBorrow = 1;
        FLLogCTestBroadcast(&context.condition);
        FLLogCTestUnlock(&context.lock);
        pthread_join(borrower, 0);
        FLLogCDestroy(context.handle);
        pthread_cond_destroy(&context.condition);
        pthread_mutex_destroy(&context.lock);
        return 0;
    }

    int didCloseRegistry = 0;
    for (unsigned int attempt = 0; attempt < 100000; attempt++) {
        if (!FLLogCInternalWithHandleBorrow(
            context.handle,
            FLLogCTestNoopBorrow,
            0
        )) {
            didCloseRegistry = 1;
            break;
        }
        sched_yield();
    }

    FLLogCTestLock(&context.lock);
    context.exerciseClosing = 1;
    FLLogCTestBroadcast(&context.condition);
    while (!context.exercisedClosing) {
        FLLogCTestWait(&context.condition, &context.lock);
    }
    int returnedBeforeRelease = context.destroyReturned;
    context.releaseBorrow = 1;
    FLLogCTestBroadcast(&context.condition);
    FLLogCTestUnlock(&context.lock);

    pthread_join(borrower, 0);
    pthread_join(destroyer, 0);

    int result =
        didCloseRegistry &&
        context.borrowResult == 1 &&
        context.closingIsEnabled == 0 &&
        returnedBeforeRelease == 0 &&
        context.destroyReturned == 1;
    pthread_cond_destroy(&context.condition);
    pthread_mutex_destroy(&context.lock);
    return result;
}

enum {
    FLLogCTestLiteralPath = 1 << 0,
    FLLogCTestEnabledPath = 1 << 1,
    FLLogCTestStructuredPath = 1 << 2,
    FLLogCTestPrintfPath = 1 << 3,
    FLLogCTestAllPaths = (1 << 4) - 1,
};

typedef struct {
    FLLogCHandle handle;
    pthread_mutex_t lock;
    pthread_cond_t condition;
    unsigned int readyWorkers;
    unsigned int pathMask;
    int didStart;
    int shouldRun;
} FLLogCTestStressContext;

typedef struct {
    FLLogCTestStressContext *context;
    unsigned int index;
} FLLogCTestStressWorker;

static unsigned int FLLogCTestExercisePath(
    FLLogCHandle handle,
    unsigned int path
) {
    switch (path) {
        case 0:
            FLLogCInfoH(handle, "concurrent literal");
            FLLogCLogH(
                handle,
                FL_LOG_LEVEL_ERROR,
                FL_LOG_PRIVACY_PRIVATE,
                "concurrent explicit"
            );
            return FLLogCTestLiteralPath;
        case 1:
            (void)FLLogCIsEnabledH(handle, FL_LOG_LEVEL_DEBUG);
            return FLLogCTestEnabledPath;
        case 2: {
            FLLogCFields fields = {
                .component = "lifecycle",
                .phase = "stress",
                .errorCode = 0,
                .correlationID = "worker-1",
            };
            FLLogCLogStructuredH(
                handle,
                FL_LOG_LEVEL_WARN,
                FL_LOG_PRIVACY_PRIVATE,
                &fields,
                "concurrent structured"
            );
            return FLLogCTestStructuredPath;
        }
        default:
            FLLogCLogfPrivacyH(
                handle,
                FL_LOG_LEVEL_INFO,
                FL_LOG_PRIVACY_PUBLIC,
                "concurrent printf %u",
                path
            );
            return FLLogCTestPrintfPath;
    }
}

static void *FLLogCTestStressThread(void *rawWorker) {
    FLLogCTestStressWorker *worker = rawWorker;
    FLLogCTestStressContext *context = worker->context;

    FLLogCTestLock(&context->lock);
    context->readyWorkers += 1;
    FLLogCTestBroadcast(&context->condition);
    while (!context->didStart) {
        FLLogCTestWait(&context->condition, &context->lock);
    }
    FLLogCTestUnlock(&context->lock);

    unsigned int path = worker->index % 4;
    while (1) {
        FLLogCTestLock(&context->lock);
        int shouldRun = context->shouldRun;
        FLLogCTestUnlock(&context->lock);
        if (!shouldRun) break;

        unsigned int completedPath = FLLogCTestExercisePath(
            context->handle,
            path
        );
        path = (path + 1) % 4;

        FLLogCTestLock(&context->lock);
        context->pathMask |= completedPath;
        FLLogCTestBroadcast(&context->condition);
        FLLogCTestUnlock(&context->lock);
    }
    return 0;
}

static int FLLogCTestRunTeardownStressIteration(unsigned int workerCount) {
    FLLogCTestStressContext context = {0};
    context.shouldRun = 1;
    context.handle = FLLogCCreate(
        "com.forgelogkit.tests",
        "ConcurrentTeardown"
    );
    if (!context.handle) return 0;
    if (pthread_mutex_init(&context.lock, 0) != 0) {
        FLLogCDestroy(context.handle);
        return 0;
    }
    if (pthread_cond_init(&context.condition, 0) != 0) {
        pthread_mutex_destroy(&context.lock);
        FLLogCDestroy(context.handle);
        return 0;
    }

    pthread_t *threads = calloc(workerCount, sizeof(*threads));
    FLLogCTestStressWorker *workers = calloc(workerCount, sizeof(*workers));
    if (!threads || !workers) {
        free(threads);
        free(workers);
        pthread_cond_destroy(&context.condition);
        pthread_mutex_destroy(&context.lock);
        FLLogCDestroy(context.handle);
        return 0;
    }

    unsigned int createdWorkers = 0;
    for (; createdWorkers < workerCount; createdWorkers++) {
        workers[createdWorkers].context = &context;
        workers[createdWorkers].index = createdWorkers;
        if (pthread_create(
            &threads[createdWorkers],
            0,
            FLLogCTestStressThread,
            &workers[createdWorkers]
        ) != 0) break;
    }

    FLLogCTestLock(&context.lock);
    if (createdWorkers == workerCount) {
        while (context.readyWorkers < workerCount) {
            FLLogCTestWait(&context.condition, &context.lock);
        }
        context.didStart = 1;
        FLLogCTestBroadcast(&context.condition);
        while (context.pathMask != FLLogCTestAllPaths) {
            FLLogCTestWait(&context.condition, &context.lock);
        }
    }
    context.shouldRun = 0;
    context.didStart = 1;
    FLLogCTestBroadcast(&context.condition);
    FLLogCTestUnlock(&context.lock);

    FLLogCDestroy(context.handle);
    for (unsigned int index = 0; index < createdWorkers; index++) {
        pthread_join(threads[index], 0);
    }

    int result =
        createdWorkers == workerCount &&
        context.pathMask == FLLogCTestAllPaths;
    free(threads);
    free(workers);
    pthread_cond_destroy(&context.condition);
    pthread_mutex_destroy(&context.lock);
    return result;
}

int FLLogCTestConcurrentHandleTeardown(
    unsigned int iterations,
    unsigned int workerCount
) {
    if (iterations == 0 || workerCount == 0 || workerCount > 16) return 0;

    for (unsigned int iteration = 0; iteration < iterations; iteration++) {
        if (!FLLogCTestRunTeardownStressIteration(workerCount)) return 0;
    }
    return 1;
}

int FLLogCTestDefensivelyRejectsImmediateStaleHandle(void) {
    FLLogCHandle handle = FLLogCCreate(
        "com.forgelogkit.tests",
        "ImmediateStaleHandle"
    );
    if (!handle) return 0;

    FLLogCDestroy(handle);
    FLLogCTestExerciseAllHandlePaths(handle);
    int isEnabled = FLLogCIsEnabledH(handle, FL_LOG_LEVEL_INFO);
    FLLogCDestroy(handle);
    return isEnabled == 0;
}

const char *FLLogCTestEventMessage(const FLLogCTestEvent *event) {
    return event ? event->message : 0;
}

unsigned char FLLogCTestEventLogType(const FLLogCTestEvent *event) {
    return event ? event->logType : 0;
}

int FLLogCTestEventIsPublic(const FLLogCTestEvent *event) {
    return event ? event->isPublic : 0;
}
