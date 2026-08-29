#include "FLLogC.h"

#include <ctype.h>
#include <stdint.h>
#include <string.h>

#ifndef FL_LOG_MAX_INPUT_BYTES
#define FL_LOG_MAX_INPUT_BYTES 65536
#endif

typedef struct {
    char *buffer;
    size_t capacity;
    size_t count;
    int overflowed;
} FLRedactionWriter;

typedef enum {
    FL_REDACT_TOKEN_VALUE,
    FL_REDACT_LINE_VALUE,
} FLSensitiveValueKind;

typedef struct {
    const char *name;
    size_t length;
    FLSensitiveValueKind valueKind;
} FLSensitiveField;

#define FL_FIELD(name, kind) { name, sizeof(name) - 1, kind }

static const FLSensitiveField FLSensitiveFields[] = {
    FL_FIELD("proxy-authorization", FL_REDACT_LINE_VALUE),
    FL_FIELD("refresh_token", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("access_token", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("authorization", FL_REDACT_LINE_VALUE),
    FL_FIELD("set-cookie", FL_REDACT_LINE_VALUE),
    FL_FIELD("private_key", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("proxy_url", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("x-api-key", FL_REDACT_LINE_VALUE),
    FL_FIELD("password", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("api_key", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("passwd", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("apikey", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("cookie", FL_REDACT_LINE_VALUE),
    FL_FIELD("secret", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("token", FL_REDACT_TOKEN_VALUE),
    FL_FIELD("pwd", FL_REDACT_TOKEN_VALUE),
};

static const char FLRedactedValue[] = "<redacted>";
static const char FLRedactedPrivateKey[] = "<redacted-private-key>";

static int FLIsNameCharacter(char character) {
    unsigned char value = (unsigned char)character;
    return isalnum(value) || character == '_' || character == '-';
}

static int FLIsValueDelimiter(char character) {
    unsigned char value = (unsigned char)character;
    return isspace(value) || character == ',' || character == ';' ||
        character == '&' || character == ']' || character == '}';
}

static int FLEqualsIgnoringCase(
    const char *input,
    size_t inputLength,
    size_t index,
    const char *expected,
    size_t expectedLength
) {
    if (expectedLength > inputLength - index) return 0;

    for (size_t offset = 0; offset < expectedLength; offset++) {
        unsigned char actual = (unsigned char)input[index + offset];
        unsigned char wanted = (unsigned char)expected[offset];
        if (tolower(actual) != tolower(wanted)) return 0;
    }
    return 1;
}

static void FLAppend(
    FLRedactionWriter *writer,
    const char *bytes,
    size_t length
) {
    if (writer->overflowed) return;
    if (length > SIZE_MAX - writer->count) {
        writer->overflowed = 1;
        return;
    }

    if (writer->buffer && writer->capacity > 0 &&
        writer->count < writer->capacity - 1) {
        size_t writable = writer->capacity - 1 - writer->count;
        if (writable > length) writable = length;
        for (size_t offset = 0; offset < writable; offset++) {
            writer->buffer[writer->count + offset] = bytes[offset];
        }
    }
    writer->count += length;
}

static int FLMatchSensitiveField(
    const char *input,
    size_t inputLength,
    size_t index,
    size_t *replacementStart,
    size_t *replacementEnd
) {
    if (index > 0 && FLIsNameCharacter(input[index - 1])) return 0;

    for (size_t fieldIndex = 0;
         fieldIndex < sizeof(FLSensitiveFields) / sizeof(FLSensitiveFields[0]);
         fieldIndex++) {
        const FLSensitiveField *field = &FLSensitiveFields[fieldIndex];
        if (!FLEqualsIgnoringCase(
            input,
            inputLength,
            index,
            field->name,
            field->length
        )) continue;

        size_t cursor = index + field->length;
        if (cursor < inputLength && FLIsNameCharacter(input[cursor])) continue;
        if (cursor < inputLength &&
            (input[cursor] == '\'' || input[cursor] == '"')) cursor++;
        while (cursor < inputLength && isspace((unsigned char)input[cursor]) &&
               input[cursor] != '\r' && input[cursor] != '\n') cursor++;
        if (cursor >= inputLength ||
            (input[cursor] != '=' && input[cursor] != ':')) continue;

        cursor++;
        while (cursor < inputLength && isspace((unsigned char)input[cursor]) &&
               input[cursor] != '\r' && input[cursor] != '\n') cursor++;

        char quote = 0;
        if (cursor < inputLength &&
            (input[cursor] == '\'' || input[cursor] == '"')) {
            quote = input[cursor];
            cursor++;
        }
        *replacementStart = cursor;

        if (quote) {
            int escaped = 0;
            while (cursor < inputLength) {
                char character = input[cursor];
                if (!escaped && character == quote) break;
                escaped = !escaped && character == '\\';
                if (character != '\\') escaped = 0;
                cursor++;
            }
        } else if (field->valueKind == FL_REDACT_LINE_VALUE) {
            while (cursor < inputLength && input[cursor] != '\r' &&
                   input[cursor] != '\n') cursor++;
        } else {
            while (cursor < inputLength && !FLIsValueDelimiter(input[cursor])) {
                cursor++;
            }
        }

        *replacementEnd = cursor;
        return 1;
    }
    return 0;
}

static int FLMatchCredentialURL(
    const char *input,
    size_t inputLength,
    size_t index,
    size_t *replacementStart,
    size_t *replacementEnd
) {
    if (!isalpha((unsigned char)input[index]) ||
        (index > 0 && FLIsNameCharacter(input[index - 1]))) return 0;

    size_t cursor = index + 1;
    while (cursor < inputLength) {
        unsigned char value = (unsigned char)input[cursor];
        if (!(isalnum(value) || input[cursor] == '+' || input[cursor] == '-' ||
              input[cursor] == '.')) break;
        cursor++;
    }
    if (cursor + 3 > inputLength || input[cursor] != ':' ||
        input[cursor + 1] != '/' || input[cursor + 2] != '/') return 0;

    size_t authorityStart = cursor + 3;
    cursor = authorityStart;
    while (cursor < inputLength) {
        char character = input[cursor];
        if (character == '@' && cursor > authorityStart) {
            *replacementStart = authorityStart;
            *replacementEnd = cursor;
            return 1;
        }
        if (isspace((unsigned char)character) || character == '/' ||
            character == '?' || character == '#' || character == ',' ||
            character == ';' || character == ']' || character == ')') break;
        cursor++;
    }
    return 0;
}

static const char *FLFindBytes(
    const char *input,
    size_t inputLength,
    const char *expected,
    size_t expectedLength
) {
    if (expectedLength > inputLength) return NULL;
    size_t finalIndex = inputLength - expectedLength;
    for (size_t index = 0; index <= finalIndex; index++) {
        if (memcmp(input + index, expected, expectedLength) == 0) {
            return input + index;
        }
    }
    return NULL;
}

static int FLMatchPrivateKey(
    const char *input,
    size_t inputLength,
    size_t index,
    size_t *replacementEnd
) {
    static const char beginMarker[] = "-----BEGIN ";
    static const char privateKeyMarker[] = "PRIVATE KEY-----";
    static const char endMarker[] = "-----END ";

    if (!FLEqualsIgnoringCase(
        input,
        inputLength,
        index,
        beginMarker,
        sizeof(beginMarker) - 1
    )) return 0;

    size_t lineEnd = index;
    while (lineEnd < inputLength && input[lineEnd] != '\r' &&
           input[lineEnd] != '\n') lineEnd++;
    if (!FLFindBytes(
        input + index,
        lineEnd - index,
        privateKeyMarker,
        sizeof(privateKeyMarker) - 1
    )) return 0;

    const char *end = FLFindBytes(
        input + lineEnd,
        inputLength - lineEnd,
        endMarker,
        sizeof(endMarker) - 1
    );
    if (!end) {
        *replacementEnd = inputLength;
        return 1;
    }

    size_t endOffset = (size_t)(end - input);
    const char *endLabel = FLFindBytes(
        input + endOffset,
        inputLength - endOffset,
        privateKeyMarker,
        sizeof(privateKeyMarker) - 1
    );
    *replacementEnd = endLabel
        ? (size_t)(endLabel - input) + sizeof(privateKeyMarker) - 1
        : inputLength;
    return 1;
}

size_t FLLogCRedactMessage(
    const char *message,
    char *buffer,
    size_t capacity
) {
    if (!message) {
        if (buffer && capacity > 0) buffer[0] = '\0';
        return 0;
    }

    size_t inputLength = strnlen(message, FL_LOG_MAX_INPUT_BYTES);
    if (inputLength == FL_LOG_MAX_INPUT_BYTES) {
        if (buffer && capacity > 0) buffer[0] = '\0';
        return 0;
    }
    FLRedactionWriter writer = { buffer, capacity, 0, 0 };
    size_t copyStart = 0;
    size_t index = 0;

    while (index < inputLength) {
        size_t replacementStart = 0;
        size_t replacementEnd = 0;
        const char *replacement = FLRedactedValue;
        size_t replacementLength = sizeof(FLRedactedValue) - 1;

        if (FLMatchPrivateKey(message, inputLength, index, &replacementEnd)) {
            replacementStart = index;
            replacement = FLRedactedPrivateKey;
            replacementLength = sizeof(FLRedactedPrivateKey) - 1;
        } else if (!FLMatchSensitiveField(
            message,
            inputLength,
            index,
            &replacementStart,
            &replacementEnd
        ) && !FLMatchCredentialURL(
            message,
            inputLength,
            index,
            &replacementStart,
            &replacementEnd
        )) {
            index++;
            continue;
        }

        FLAppend(&writer, message + copyStart, replacementStart - copyStart);
        FLAppend(&writer, replacement, replacementLength);
        index = replacementEnd;
        copyStart = replacementEnd;
    }

    FLAppend(&writer, message + copyStart, inputLength - copyStart);
    if (buffer && capacity > 0) {
        size_t terminator = writer.count < capacity ? writer.count : capacity - 1;
        buffer[terminator] = '\0';
    }
    if (writer.overflowed || writer.count == SIZE_MAX) return 0;
    return writer.count + 1;
}
