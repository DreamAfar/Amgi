//! C ABI bridge for the Anki Rust backend.
//!
//! Exposes functions matching the pattern used by AnkiDroid's JNI bridge,
//! adapted for C ABI (Swift interop via XCFramework).

use std::os::raw::c_int;
use std::slice;

use anki::backend::{init_backend, Backend};
use prost::Message;
use serde_json::json;
use serde_json::Value;

// ──────────────────────────────────────────────────────────
// Batch note fetch
// ──────────────────────────────────────────────────────────

/// Fetch multiple notes in a single FFI call.
///
/// Request encoding (binary, little-endian):
///   [count: u32_le] [nid_0: i64_le] ... [nid_N: i64_le]
///
/// Response encoding:
///   [count: u32_le] [len_0: u32_le] [note_bytes_0] ... [len_N: u32_le] [note_bytes_N]
///
/// Each `note_bytes_i` is a valid serialized `anki_proto::notes::Note` protobuf.
/// Missing note IDs are silently omitted (count may be < requested count).
///
/// # Safety
/// - `backend_ptr` must be a valid pointer from `anki_open_backend`.
/// - `req_data` / `req_len` must describe a valid request buffer.
#[no_mangle]
pub unsafe extern "C" fn anki_get_notes_batch(
    backend_ptr: i64,
    req_data: *const u8,
    req_len: usize,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    let backend = unsafe { &*(backend_ptr as *const Backend) };

    if req_data.is_null() || req_len < 4 {
        return -1;
    }
    let input = unsafe { slice::from_raw_parts(req_data, req_len) };

    // Decode request header
    let count = u32::from_le_bytes([input[0], input[1], input[2], input[3]]) as usize;
    if req_len < 4 + count * 8 {
        return -1;
    }

    // Decode note IDs from request
    let mut note_ids: Vec<i64> = Vec::with_capacity(count);
    for i in 0..count {
        let off = 4 + i * 8;
        let nid = i64::from_le_bytes(input[off..off + 8].try_into().unwrap());
        note_ids.push(nid);
    }

    if note_ids.is_empty() {
        set_output(0u32.to_le_bytes().to_vec(), out_data, out_len);
        return 0;
    }

    // One SQL query for all requested IDs.
    let placeholders = vec!["?"; note_ids.len()].join(",");
    let sql = format!(
        "select id, guid, mid, mod, usn, tags, flds from notes where id in ({})",
        placeholders
    );
    let args: Vec<Value> = note_ids.iter().map(|nid| json!(nid)).collect();
    let db_req = json!({
        "kind": "query",
        "sql": sql,
        "args": args,
        "first_row_only": false,
    });

    let db_req_bytes = match serde_json::to_vec(&db_req) {
        Ok(bytes) => bytes,
        Err(_) => return -1,
    };

    let db_resp_bytes = match backend.run_db_command_bytes(&db_req_bytes) {
        Ok(bytes) => bytes,
        Err(err_bytes) => {
            // Keep parity with anki_run_method(): backend errors return 1 with protobuf bytes.
            set_output(err_bytes, out_data, out_len);
            return 1;
        }
    };

    // DbResult::Rows serializes to JSON array rows: [[col0, col1, ...], ...]
    let rows: Vec<Vec<Value>> = match serde_json::from_slice(&db_resp_bytes) {
        Ok(rows) => rows,
        Err(_) => return -1,
    };

    // Convert SQL rows into Note protobuf bytes.
    let mut by_id: std::collections::HashMap<i64, Vec<u8>> = std::collections::HashMap::new();
    by_id.reserve(rows.len());
    for row in rows {
        if row.len() < 7 {
            continue;
        }

        let Some(id) = row[0].as_i64() else { continue };
        let Some(guid) = row[1].as_str() else { continue };
        let Some(mid) = row[2].as_i64() else { continue };
        let Some(mod_secs) = row[3].as_i64() else { continue };
        let Some(usn_raw) = row[4].as_i64() else { continue };
        let tags_raw = row[5].as_str().unwrap_or_default();
        let fields_raw = row[6].as_str().unwrap_or_default();

        let note = anki_proto::notes::Note {
            id,
            guid: guid.to_string(),
            notetype_id: mid,
            mtime_secs: mod_secs as u32,
            usn: usn_raw as i32,
            tags: tags_raw
                .split_whitespace()
                .map(ToString::to_string)
                .collect(),
            fields: fields_raw.split('\x1f').map(ToString::to_string).collect(),
        };
        by_id.insert(id, note.encode_to_vec());
    }

    // Preserve caller order; omit IDs not found.
    let mut all_notes: Vec<Vec<u8>> = Vec::with_capacity(note_ids.len());
    for nid in note_ids {
        if let Some(bytes) = by_id.remove(&nid) {
            all_notes.push(bytes);
        }
    }

    // Encode response
    let note_count = all_notes.len();
    let body_len: usize = all_notes.iter().map(|b| 4 + b.len()).sum();
    let mut response: Vec<u8> = Vec::with_capacity(4 + body_len);
    response.extend_from_slice(&(note_count as u32).to_le_bytes());
    for note in &all_notes {
        response.extend_from_slice(&(note.len() as u32).to_le_bytes());
        response.extend_from_slice(note);
    }

    set_output(response, out_data, out_len);
    0
}

/// Create a new Anki backend instance.
///
/// # Safety
/// - `init_data` must point to a valid buffer of `init_len` bytes containing
///   a serialized `BackendInit` protobuf message (or be null for defaults).
/// - `out_ptr` must point to writable memory for a single i64.
///
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn anki_open_backend(
    init_data: *const u8,
    init_len: usize,
    out_ptr: *mut i64,
) -> c_int {
    let init_bytes: &[u8] = if init_data.is_null() || init_len == 0 {
        // Empty init → default BackendInit (empty preferred_langs, server=false)
        b""
    } else {
        unsafe { slice::from_raw_parts(init_data, init_len) }
    };

    // If empty bytes, encode a default BackendInit
    let effective_bytes: Vec<u8>;
    let bytes_to_use = if init_bytes.is_empty() {
        use prost::Message;
        let default_init = anki_proto::backend::BackendInit::default();
        effective_bytes = default_init.encode_to_vec();
        &effective_bytes
    } else {
        init_bytes
    };

    match init_backend(bytes_to_use) {
        Ok(backend) => {
            let boxed = Box::new(backend);
            let ptr = Box::into_raw(boxed) as i64;
            unsafe { *out_ptr = ptr };
            0
        }
        Err(_e) => -1,
    }
}

/// Execute a backend RPC method via protobuf.
///
/// # Safety
/// - `backend_ptr` must be a valid pointer returned by `anki_open_backend`.
/// - `input_data`/`input_len` must describe a valid protobuf request.
/// - `out_data`/`out_len` receive the response (caller frees with `anki_free_response`).
///
/// Returns 0 on success (out_data has the response protobuf),
///         1 on backend error (out_data has the error protobuf),
///        -1 on FFI error.
#[no_mangle]
pub unsafe extern "C" fn anki_run_method(
    backend_ptr: i64,
    service: u32,
    method: u32,
    input_data: *const u8,
    input_len: usize,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    let backend = unsafe { &*(backend_ptr as *const Backend) };

    let input = if input_data.is_null() || input_len == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(input_data, input_len) }
    };

    match backend.run_service_method(service, method, input) {
        Ok(output) => {
            set_output(output, out_data, out_len);
            0 // success
        }
        Err(err_bytes) => {
            set_output(err_bytes, out_data, out_len);
            1 // backend error (response contains error protobuf)
        }
    }
}

/// Free a response buffer allocated by `anki_run_method`.
#[no_mangle]
pub unsafe extern "C" fn anki_free_response(data: *mut u8, len: usize) {
    if !data.is_null() && len > 0 {
        let _ = unsafe { Vec::from_raw_parts(data, len, len) };
    }
}

/// Close and destroy the backend instance.
#[no_mangle]
pub unsafe extern "C" fn anki_close_backend(backend_ptr: i64) {
    if backend_ptr != 0 {
        let _ = unsafe { Box::from_raw(backend_ptr as *mut Backend) };
    }
}

// -- Helpers --

unsafe fn set_output(data: Vec<u8>, out_data: *mut *mut u8, out_len: *mut usize) {
    let len = data.len();
    if len > 0 {
        let mut boxed = data.into_boxed_slice();
        let ptr = boxed.as_mut_ptr();
        std::mem::forget(boxed);
        unsafe {
            *out_data = ptr;
            *out_len = len;
        }
    } else {
        unsafe {
            *out_data = std::ptr::null_mut();
            *out_len = 0;
        }
    }
}
