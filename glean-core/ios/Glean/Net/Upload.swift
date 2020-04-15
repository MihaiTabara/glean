/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Translation of FFI-compatible types of the upload module into Swift types.
///
/// For FFI-compatibility we pass "tagged enums" back and forth for the upload module.
/// These have a format like this in C (simplified), generated by `cbindgen`:
///
/// ```
/// enum Task_Tag { Upload, Wait };
/// typedef uint8_t Task_Tag;
///
/// typedef struct {
///   Task_Tag tag;
///   char *data
/// } Task_Upload;
///
/// typedef struct {
///  Task_Tag tag;
/// } Task_Wait;
///
/// typedef union {
///   Task_Upload upload;
///   Task_Wait wait;
/// } Task;
/// ```
///
/// (in reality C/cbindgen is smart enough to merge the tag of data-less variants into the union).
///
/// Swift allows direct interaction with C structs and unions[1].
/// However, the `Task_Tag` enum is represented as a 32-bit unsigned integer.
/// The tag in the unionized structs (`Task_Upload`, `Task_Wait`) is represented as a 8-bit unsigned integer.
/// In C that is fine and comparisons between these two types get promoted to the bigger integer anyway.
/// In Swift the type-checking is more strict, so we need to manually convert it.
/// Additionally because both the enum and the typedef for the tag have the same name
/// (a thing we can't easily fix right now in cbindgen), it's hard to distinguish between them in Swift code.
///
/// [1]: https://developer.apple.com/documentation/swift/imported_c_and_objective-c_apis/using_imported_c_structs_and_unions_in_swift

/// A ping request contains all data required to upload a ping
struct PingRequest {
    /// The unique identifier of the string. This is also the filename on disk.
    let uuid: String
    /// The path to upload this ping to.
    let path: String
    /// The JSON-encoded payload of the ping.
    let body: String
    /// A map of headers for the HTTP request to send.
    let headers: [String: String]

    init(uuid: String, path: String, body: String, headers: [String: String]) {
        self.uuid = uuid
        self.path = path
        self.body = body

        var headers = headers
        if let pingTag = Glean.shared.configuration?.pingTag {
            headers["X-Debug-ID"] = pingTag
        }

        self.headers = headers
    }
}

/// A Swift representation of the different tasks to be worked on
enum PingUploadTask {
    /// Upload the wrapped request.
    case upload(PingRequest)

    /// Wait, then ask for the next task.
    case wait

    /// Work is finished.
    case done
}

extension FfiPingUploadTask {
    /// Translate the FFI representation of a task to its Swift equivalent
    func toPingUploadTask() -> PingUploadTask {
        /// This is manually converting between the different types.
        ///
        /// What we would _like to do is just:
        ///
        /// ```
        /// let tag = FfiPingUploadTask_Tag(rawValue: UInt32(self.tag))
        /// ```
        ///
        /// and then compare that to `FfiPingUploadTask_Upload` or similar.
        /// However right now that leads to a crash with `error: Abort trap: 6`
        /// during _compilation_ of this code.
        ///
        /// We therefore go the manual way and compare the integers only.
        switch UInt32(self.tag) {
        case FfiPingUploadTask_Upload.rawValue:
            return .upload(self.upload.toPingRequest())
        case FfiPingUploadTask_Wait.rawValue:
            return .wait
        case FfiPingUploadTask_Done.rawValue:
            return .done
        default:
            // Tag can only be one of the enum values,
            // therefore we can't reach this point
            assertUnreachable()
        }
    }
}

extension FfiPingUploadTask_Upload_Body {
    /// Translate the FFI representation of a request to its Swift equivalent.
    ///
    /// This decodes the JSON-encoded header map into a native map.
    /// If decoding as a string-to-string map fails, an empty map is used.
    func toPingRequest() -> PingRequest {
        let uuid = String(cString: self.uuid)
        let path = String(cString: self.path)
        let body = String(cString: self.body)

        // Decode the header object from JSON
        let json = String(cString: self.headers)
        let data = json.data(using: .utf8)!
        let headers = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]

        return PingRequest(uuid: uuid, path: path, body: body, headers: headers ?? [String: String]())
    }
}