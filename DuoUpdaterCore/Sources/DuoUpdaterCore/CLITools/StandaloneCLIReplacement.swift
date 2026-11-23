import Darwin
import Foundation

/// Detect a rename and in-place edits, including changes made while an archive
/// is downloading. lstat is used at the original path, including at commit.
struct StandaloneCLIFileStamp: Sendable, Equatable {
    let identity: CLIToolProcesses.FileID
    let links: UInt16
    let owner: uid_t
    let group: gid_t
    let mode: mode_t
    let bytes: off_t
    let changedSeconds: Int
    let changedNanoseconds: Int

    init?(_ info: stat) {
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0,
              info.st_size <= 128 * 1024 * 1024, info.st_mode & 0o111 != 0
        else { return nil }
        identity = .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
        links = info.st_nlink
        owner = info.st_uid
        group = info.st_gid
        mode = info.st_mode
        bytes = info.st_size
        changedSeconds = info.st_ctimespec.tv_sec
        changedNanoseconds = info.st_ctimespec.tv_nsec
    }

    static func read(at path: String) -> Self? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Self(info)
    }
}

enum StandaloneCLIReplacement {
    enum Failure: LocalizedError {
        case changed
        case inProgress
        case unsafeStaging
        case system(Int32)

        var errorDescription: String? {
            switch self {
            case .changed: "The installation changed after checking. Check for updates again."
            case .inProgress: "Another update is replacing this executable. Try again once it finishes."
            case .unsafeStaging: "DuoUpdater could not create a private staging directory."
            case .system(let code): "Could not replace the executable: \(String(cString: strerror(code)))"
            }
        }
    }

    /// Stage on the same volume, then replace with one rename. Anchor writes to
    /// the checked directory's descriptor so swapping a parent symlink cannot
    /// send the temporary file or replacement somewhere else.
    static func replace(
        at path: String, original: StandaloneCLIFileStamp, directory directoryID: CLIToolProcesses.FileID,
        with executable: URL, recheck: () throws -> Void
    ) throws {
        let name = (path as NSString).lastPathComponent
        let directory = (path as NSString).deletingLastPathComponent
        let parent = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw Failure.system(errno) }
        defer { close(parent) }
        var directoryInfo = stat()
        guard fstat(parent, &directoryInfo) == 0,
              fileID(directoryInfo) == directoryID
        else { throw Failure.changed }

        // App and duo can both hold an offer for this inode. Keep the
        // original descriptor locked through recheck and rename.
        let currentFile = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard currentFile >= 0 else { throw Failure.changed }
        defer { close(currentFile) }
        var current = stat()
        guard fstat(currentFile, &current) == 0, StandaloneCLIFileStamp(current) == original else {
            throw Failure.changed
        }
        guard flock(currentFile, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            throw code == EWOULDBLOCK ? Failure.inProgress : Failure.system(code)
        }

        let source = open(executable.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard source >= 0 else { throw Failure.system(errno) }
        defer { close(source) }

        // Even another writer of the bin directory must not be able to swap
        // out the verified source before renameat. Give the source its own
        // private directory and perform the rename relative to that descriptor.
        let temporary = ".duo-cli-\(UUID().uuidString)"
        guard mkdirat(parent, temporary, 0o700) == 0 else { throw Failure.system(errno) }
        let stageDirectory = openat(parent, temporary, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stageDirectory >= 0 else { throw Failure.system(errno) }
        defer { close(stageDirectory) }
        var stageDirectoryInfo = stat()
        guard fstat(stageDirectory, &stageDirectoryInfo) == 0, stageDirectoryInfo.st_uid == geteuid()
        else { throw Failure.unsafeStaging }
        defer {
            var entry = stat()
            if fstatat(parent, temporary, &entry, AT_SYMLINK_NOFOLLOW) == 0,
               fileID(entry) == fileID(stageDirectoryInfo) {
                unlinkat(parent, temporary, AT_REMOVEDIR)
            }
        }
        guard stageDirectoryInfo.st_mode & 0o777 == 0o700 else { throw Failure.unsafeStaging }
        // An inherited ACL could give someone access despite mode 0700.
        if let acl = acl_get_fd_np(stageDirectory, ACL_TYPE_EXTENDED) {
            acl_free(UnsafeMutableRawPointer(acl))
            throw Failure.unsafeStaging
        }
        let aclError = errno
        guard aclError == ENOENT || aclError == ENOATTR || aclError == ENOTSUP else { throw Failure.unsafeStaging }

        let stage = openat(stageDirectory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard stage >= 0 else { throw Failure.system(errno) }
        defer {
            close(stage)
            unlinkat(stageDirectory, name, 0)
        }
        guard fcopyfile(source, stage, nil, copyfile_flags_t(COPYFILE_DATA)) == 0,
              fchown(stage, original.owner, original.group) == 0,
              fchmod(stage, original.mode & 0o777) == 0
        else { throw Failure.system(errno) }

        // COPYFILE_ACL omits inherited entries. Copy the original ACL directly
        // because the replacement's private staging directory supplies none.
        if let acl = acl_get_fd_np(currentFile, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            guard acl_set_fd_np(stage, acl, ACL_TYPE_EXTENDED) == 0 else { throw Failure.system(errno) }
        } else {
            let code = errno
            guard code == ENOENT || code == ENOATTR || code == ENOTSUP else { throw Failure.system(code) }
        }
        guard fsync(stage) == 0 else { throw Failure.system(errno) }

        var stagedInfo = stat()
        guard fstat(stage, &stagedInfo) == 0, let stagedFile = StandaloneCLIFileStamp(stagedInfo)
        else { throw Failure.changed }
        try recheck()
        guard fstatat(stageDirectory, name, &stagedInfo, AT_SYMLINK_NOFOLLOW) == 0,
              StandaloneCLIFileStamp(stagedInfo) == stagedFile
        else { throw Failure.changed }
        guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              StandaloneCLIFileStamp(current) == original
        else { throw Failure.changed }
        guard renameat(stageDirectory, name, parent, name) == 0 else { throw Failure.system(errno) }
    }

    private static func fileID(_ info: stat) -> CLIToolProcesses.FileID {
        .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }
}
