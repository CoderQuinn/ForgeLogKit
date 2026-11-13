#pragma once
#include <stdint.h>
#include <stddef.h>
typedef struct {
    uint64_t elapsed_ns;
    size_t created, completed, joined, submitted, destroyed;
    int valid;
} FLBenchResult;
int FLBenchLifetimeReady(size_t created, size_t joined, size_t active, size_t destroyed);
FLBenchResult FLBenchProducers(size_t producers, size_t iterations, const char *input, const char *expected);
