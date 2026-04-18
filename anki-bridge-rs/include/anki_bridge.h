#ifndef ANKI_BRIDGE_H
#define ANKI_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

/**
 * Create a new Anki backend instance.
 *
 * @param init_data  Pointer to serialized BackendInit protobuf bytes (may be NULL for defaults).
 * @param init_len   Length of init_data in bytes.
 * @param out_ptr    On success, receives an opaque backend pointer (as int64_t).
 * @return 0 on success, -1 on error.
 */
int anki_open_backend(const uint8_t *init_data, size_t init_len, int64_t *out_ptr);

/**
 * Execute a backend RPC method.
 *
 * @param backend_ptr  Opaque pointer from anki_open_backend.
 * @param service      Protobuf service ID.
 * @param method       Protobuf method ID within the service.
 * @param input_data   Serialized protobuf request bytes.
 * @param input_len    Length of input_data.
 * @param out_data     On success, receives a pointer to the response bytes (heap-allocated).
 * @param out_len      On success, receives the length of out_data.
 * @return 0 on success, -1 on error.
 */
int anki_run_method(
    int64_t backend_ptr,
    uint32_t service,
    uint32_t method,
    const uint8_t *input_data,
    size_t input_len,
    uint8_t **out_data,
    size_t *out_len
);

/**
 * Free a response buffer returned by anki_run_method.
 *
 * @param data  Pointer from out_data (may be NULL).
 * @param len   Length from out_len.
 */
void anki_free_response(uint8_t *data, size_t len);

/**
 * Close and destroy the backend instance.
 *
 * @param backend_ptr  Opaque pointer from anki_open_backend. Invalid after this call.
 */
void anki_close_backend(int64_t backend_ptr);

/**
 * Fetch multiple notes in a single call (batch optimisation).
 *
 * Request format (binary, little-endian):
 *   [count: uint32_t] [nid_0: int64_t] ... [nid_N: int64_t]
 *
 * Response format:
 *   [count: uint32_t] [len_0: uint32_t] [note_proto_0] ... [len_N: uint32_t] [note_proto_N]
 *
 * Each note_proto_i is a serialized anki.notes.Note protobuf message.
 * Notes that cannot be found are silently omitted.
 *
 * @param backend_ptr   Opaque pointer from anki_open_backend.
 * @param req_data      Pointer to the request bytes (count + note IDs).
 * @param req_len       Length of req_data.
 * @param out_data      Receives a pointer to the response bytes (heap-allocated).
 * @param out_len       Receives the length of out_data.
 * @return 0 on success, -1 on error.
 */
int anki_get_notes_batch(
    int64_t backend_ptr,
    const uint8_t *req_data,
    size_t req_len,
    uint8_t **out_data,
    size_t *out_len
);

#endif /* ANKI_BRIDGE_H */
