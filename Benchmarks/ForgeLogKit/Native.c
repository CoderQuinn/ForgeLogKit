#include "Native.h"
#include "Capture.h"
#include "FLLogC.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// Each producer owns its capture counters. There is no shared sink lock.
static _Thread_local const char *expectedBytes;
static _Thread_local size_t submissions;
static _Thread_local int captureValid;

void FLBenchCapture(os_log_t log, os_log_type_t type, const char *format, const char *message) {
    (void)log;
    captureValid &= type == OS_LOG_TYPE_ERROR && strcmp(format, "%{private}s") == 0;
    captureValid &= expectedBytes && strcmp(message, expectedBytes) == 0;
    submissions++;
}

int FLBenchLifetimeReady(size_t created, size_t joined, size_t active, size_t destroyed) {
    return created > 0 && joined == created && active == 0 && destroyed == 0;
}

static void checked(int code) { if (code != 0) abort(); }
static uint64_t now(void) {
    struct timespec value;
    checked(clock_gettime(CLOCK_MONOTONIC_RAW, &value));
    return (uint64_t)value.tv_sec * 1000000000ULL + (uint64_t)value.tv_nsec;
}

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t condition;
    size_t ready, active;
    int go;
    FLLogCHandle handle;
    const char *input, *expected;
    size_t iterations;
} Gate;

typedef struct {
    Gate *gate;
    size_t submitted;
    int valid, completed;
} Worker;

static void *produce(void *opaque) {
    Worker *worker = opaque;
    Gate *gate = worker->gate;
    expectedBytes = gate->expected;
    submissions = 0;
    captureValid = 1;
    checked(pthread_mutex_lock(&gate->lock));
    gate->active++;
    gate->ready++;
    checked(pthread_cond_broadcast(&gate->condition));
    while (!gate->go) checked(pthread_cond_wait(&gate->condition, &gate->lock));
    checked(pthread_mutex_unlock(&gate->lock));
    for (size_t index = 0; index < gate->iterations; index++) {
        FLLogCLogH(gate->handle, FL_LOG_LEVEL_ERROR, FL_LOG_PRIVACY_PRIVATE, gate->input);
    }
    worker->submitted = submissions;
    worker->valid = captureValid && submissions == gate->iterations;
    worker->completed = 1;
    expectedBytes = NULL;
    checked(pthread_mutex_lock(&gate->lock));
    gate->active--;
    checked(pthread_mutex_unlock(&gate->lock));
    return NULL;
}

FLBenchResult FLBenchProducers(size_t producers, size_t iterations, const char *input, const char *expected) {
    FLBenchResult result = {0};
    if (!(producers == 1 || producers == 2 || producers == 4 || producers == 8) || !iterations) return result;
    Gate gate = {.lock = PTHREAD_MUTEX_INITIALIZER, .condition = PTHREAD_COND_INITIALIZER,
                 .input = input, .expected = expected, .iterations = iterations};
    gate.handle = FLLogCCreate("com.forgelogkit.benchmark", "Bench");
    if (!gate.handle) return result;
    pthread_t threads[8];
    Worker workers[8] = {0};
    for (size_t index = 0; index < producers; index++) {
        workers[index].gate = &gate;
        checked(pthread_create(&threads[index], NULL, produce, &workers[index]));
        result.created++;
    }
    checked(pthread_mutex_lock(&gate.lock));
    while (gate.ready != producers) checked(pthread_cond_wait(&gate.condition, &gate.lock));
    uint64_t start = now();
    gate.go = 1;
    checked(pthread_cond_broadcast(&gate.condition));
    checked(pthread_mutex_unlock(&gate.lock));
    result.valid = 1;
    for (size_t index = 0; index < producers; index++) {
        checked(pthread_join(threads[index], NULL));
        result.joined++;
        result.completed += workers[index].completed;
        result.submitted += workers[index].submitted;
        result.valid &= workers[index].valid;
    }
    result.elapsed_ns = now() - start;
    // Fail closed before teardown; never test by racing destruction or using a freed handle.
    if (!FLBenchLifetimeReady(result.created, result.joined, gate.active, result.destroyed)) abort();
    FLLogCDestroy(gate.handle);
    gate.handle = NULL;
    result.destroyed++;
    checked(pthread_cond_destroy(&gate.condition));
    checked(pthread_mutex_destroy(&gate.lock));
    return result;
}
