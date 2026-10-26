import Foundation
import Testing
@testable import DuoUpdaterCore

/// PEP 440 ordering, `Requires-Python` matching, PyPI's newest-for-this-Python
/// and the project-URL repository rule, which uv's and pipx's rows share.
struct PythonPackageTests {

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/pipx/\(name)"))
    }

    /// PEP 440's own example order. Mutation: compare as `VersionComparator`
    /// does (it puts `1.0rc1` above `1.0`).
    @Test func versionsOrderAsPEP440Says() throws {
        let order = ["1.0.dev0", "1.0a1", "1.0a2.dev1", "1.0a2", "1.0b1", "1.0rc1", "1.0", "1.0.post1.dev0", "1.0.post1", "1.1", "2!0.1"]
        let versions = try order.map { try #require(PythonVersion($0), "\($0)") }
        for (a, b) in zip(versions, versions.dropFirst()) {
            #expect(a < b, "\(a) < \(b)")
        }
        #expect(PythonVersion("1.0.0") == PythonVersion("1.0"))
        #expect(PythonVersion("1.0-1") == PythonVersion("1.0.post1"))
        #expect(PythonVersion("1.0rc1")?.isPrerelease == true)
        #expect(PythonVersion("1.0.post1")?.isPrerelease == false)
        #expect(PythonVersion("not a version") == nil)
    }

    @Test func specifiersAreMatched() throws {
        let python = try #require(PythonVersion("3.9.6"))
        #expect(PythonSpecifier(">=3.8")?.allows(python) == true)
        #expect(PythonSpecifier(">=3.10")?.allows(python) == false)
        #expect(PythonSpecifier(">=3.7, <4")?.allows(python) == true)
        #expect(PythonSpecifier("!=3.9.*")?.allows(python) == false)
        #expect(PythonSpecifier("==3.9.*")?.allows(python) == true)
        #expect(PythonSpecifier("~=3.8")?.allows(python) == true)
        #expect(PythonSpecifier("~=3.9.7")?.allows(python) == false)
        #expect(PythonSpecifier(">=3.6, !=3.0.*, !=3.1.*")?.allows(python) == true)
        #expect(PythonSpecifier("python3") == nil)
    }

    /// black's newest, 26.10.1, needs Python ≥3.10: a 3.9 venv gets 25.11.0,
    /// a 3.12 one 26.10.1; with `exclude-newer` before 25.11.0's upload, the
    /// one before it. Mutation: take `info.version` alone; ignore the cut-off.
    @Test func theNewestIsTheNewestThisPythonCanInstall() throws {
        let document = try #require(PyPIProject.parse(try Self.fixture("pypi-black-trimmed.json")))
        #expect(document.latest == "26.10.1")
        #expect(PyPIProject.newest(in: document, python: "3.9.6") == "25.11.0")
        #expect(PyPIProject.newest(in: document, python: "3.12.15") == "26.10.1")
        let upload = try #require(document.releases.first { $0.version == "25.11.0" }?.uploaded)
        #expect(PyPIProject.newest(in: document, python: "3.9.6", uploadedBefore: upload.addingTimeInterval(-1)) == "25.1.0")
    }

    /// An unknown Python cannot be told a requirement's answer: nil, not the
    /// newest release that states none. A latest that is all yanked is not
    /// installable. Mutation: skip a release whose answer is unknown; trust
    /// `info.version` as it is.
    @Test func unknownsAndYanksAreNotGuessedPast() throws {
        let cowsay = try #require(PyPIProject.parse(try Self.fixture("pypi-cowsay.json")))
        #expect(PyPIProject.newest(in: cowsay, python: nil) == nil)
        let yanked = PyPIProject.Document(
            latest: "2.0", latestRequiresPython: nil,
            releases: [.init(version: "1.0", requiresPython: nil, uploaded: nil, yanked: false),
                       .init(version: "2.0", requiresPython: nil, uploaded: nil, yanked: true)],
            projectURLs: [])
        #expect(PyPIProject.newest(in: yanked, python: "3.12.0") == "1.0")
    }

    @Test func aFullDocumentIsRead() throws {
        let document = try #require(PyPIProject.parse(try Self.fixture("pypi-httpie.json")))
        #expect(document.latest == "3.2.4")
        #expect(PyPIProject.newest(in: document, python: "3.12.15") == "3.2.4")
        #expect(ProjectURLRepo.repository(document.projectURLs, project: "httpie")?.owner == "httpie")
    }

    /// httpie's repository is httpie/cli (owner is the name), black's
    /// psf/black (repo is the name, found under "Changelog" first); a URL that
    /// names neither is not trusted. Mutation: take the first github.com URL.
    @Test func theRepositoryMustBeTheProjects() {
        #expect(ProjectURLRepo.repository(
            [("Homepage", "https://httpie.io"), ("GitHub", "https://github.com/httpie/cli")], project: "httpie")! == ("httpie", "cli"))
        #expect(ProjectURLRepo.repository(
            [("Documentation", "https://black.readthedocs.io/"), ("Changelog", "https://github.com/psf/black/blob/main/CHANGES.md")],
            project: "black")! == ("psf", "black"))
        #expect(ProjectURLRepo.repository([("Source", "https://github.com/ansible/ansible-documentation")], project: "ansible-core") == nil)
        // cowsay's only URL (Home-page), measured on the Mac: its repository
        // carries a Python affix, and tags v6.0, v6.1.
        #expect(ProjectURLRepo.repository([("Homepage", "https://github.com/VaasuDevanS/cowsay-python")], project: "cowsay")!
            == ("VaasuDevanS", "cowsay-python"))
        #expect(ProjectURLRepo.repository([("Source", "https://github.com/someone/cowsay-tools")], project: "cowsay") == nil)
        #expect(ProjectURLRepo.repository(
            [("Source", "https://github.com/python/typing_extensions.git")], project: "typing-extensions")! == ("python", "typing_extensions"))
    }

    /// A venv's distribution is its own dist-info, matched by normalized name.
    @Test func theDistributionIsReadByNormalizedName() {
        let site = "/v/lib/python3.12/site-packages"
        let found = PythonDistribution.read(
            "typing-extensions", venv: "/v",
            contents: { $0 == site + "/typing_extensions-4.16.0.dist-info/METADATA" ? Data("Name: typing_extensions\nVersion: 4.16.0\n\nbody".utf8) : nil },
            directories: { $0 == "/v/lib" ? ["python3.12"] : $0 == site ? ["typing_extensions-4.16.0.dist-info", "typing-1.0.dist-info"] : nil })
        #expect(found?.version == "4.16.0")
        // Two of the same name: an interrupted install, nothing to read.
        let two = PythonDistribution.read(
            "ruff", venv: "/v", contents: { _ in nil },
            directories: { $0 == "/v/lib" ? ["python3.12"] : $0 == site ? ["ruff-0.6.0.dist-info", "ruff-0.17.2.dist-info"] : nil })
        #expect(two == nil)
    }
}
