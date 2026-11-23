import Darwin
import Foundation

enum MulticaReplacement {
    enum Failure: LocalizedError {
        case changed
        case busy
        case unpublished
        case unsafeStaging
        case system(Int32)

        var errorDescription: String? {
            switch self {
            case .changed: "The Multica installation changed after checking. Check for updates again."
            case .busy: MulticaProvider.busyMessage
            case .unpublished: "The installed Multica executable differs from the official release."
            case .unsafeStaging: "DuoUpdater could not create a private staging directory for Multica."
            case .system(let code): "Could not replace Multica: \(String(cString: strerror(code)))"
            }
        }
    }

    /// Stage on the same volume, then replace with one rename. Anchor writes to
    /// the checked directory's descriptor so swapping a parent symlink cannot
    /// send the temporary file or replacement somewhere else.
    static func replace(_ installed: MulticaInstall, with executable: URL, recheck: () throws -> Void) throws {
        let directory = (installed.executable as NSString).deletingLastPathComponent
        let parent = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw Failure.system(errno) }
        defer { close(parent) }
        var directoryInfo = stat()
        guard fstat(parent, &directoryInfo) == 0,
              fileID(directoryInfo) == installed.directory
        else { throw Failure.changed }

        let source = open(executable.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard source >= 0 else { throw Failure.system(errno) }
        defer { close(source) }

        // Even another writer of the bin directory must not be able to swap
        // out the verified source before renameat. Give the source its own
        // private directory and perform the rename relative to that descriptor.
        let temporary = ".duo-multica-\(UUID().uuidString)"
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

        let stage = openat(stageDirectory, "multica", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard stage >= 0 else { throw Failure.system(errno) }
        defer {
            close(stage)
            unlinkat(stageDirectory, "multica", 0)
        }
        guard fcopyfile(source, stage, nil, copyfile_flags_t(COPYFILE_DATA)) == 0,
              fchown(stage, installed.file.owner, installed.file.group) == 0,
              fchmod(stage, installed.file.mode & 0o777) == 0,
              fsync(stage) == 0
        else { throw Failure.system(errno) }

        var stagedInfo = stat()
        guard fstat(stage, &stagedInfo) == 0, let stagedFile = MulticaFileStamp(stagedInfo)
        else { throw Failure.changed }
        try recheck()
        guard fstatat(stageDirectory, "multica", &stagedInfo, AT_SYMLINK_NOFOLLOW) == 0,
              MulticaFileStamp(stagedInfo) == stagedFile
        else { throw Failure.changed }
        var current = stat()
        guard fstatat(parent, "multica", &current, AT_SYMLINK_NOFOLLOW) == 0,
              MulticaFileStamp(current) == installed.file
        else { throw Failure.changed }
        guard renameat(stageDirectory, "multica", parent, "multica") == 0 else { throw Failure.system(errno) }
    }

    private static func fileID(_ info: stat) -> CLIToolProcesses.FileID {
        .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }
}
