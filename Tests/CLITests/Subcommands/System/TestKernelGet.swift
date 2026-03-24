//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ContainerAPIClient
import ContainerPersistence
import Containerization
import ContainerizationArchive
import Foundation
import Testing

// This suite is run serialized since each test modifies the global default kernel.
// TODO: move doKernelGet to TestCLIKernelSet so we can test it there instead of
// downloading these kernel image files all over again for these tests.
@Suite(.serialized)
class TestCLIKernelGet: CLITest {
    let defaultKernelTar = DefaultsStore.get(key: .defaultKernelURL)
    var remoteTar: URL! {
        URL(string: defaultKernelTar)
    }
    var localTarPath: URL! {
        /// A description
        set {}
        get { URL(string: "about:blank") }
    }

    let defaultBinaryPath = DefaultsStore.get(key: .defaultKernelBinaryPath)

    deinit {
        try? resetDefaultBinary()
    }

    func resetDefaultBinary() throws {
        let arguments: [String] = [
            "system",
            "kernel",
            "set",
            "--recommended",
            "--force",
        ]
        let (_, _, error, status) = try run(arguments: arguments)
        if status != 0 {
            throw CLIError.executionFailed("failed to reset kernel to recommended: \(error)")
        }
    }

    func doKernelSet(extraArgs: [String]) throws {
        var arguments = [
            "system",
            "kernel",
            "set",
            "--force",
        ]
        arguments.append(contentsOf: extraArgs)

        let (_, _, error, status) = try run(arguments: arguments)
        if status != 0 {
            throw CLIError.executionFailed("failed to set kernel: \(error)")
        }
    }

    func doKernelGet(expectedLastPathComponent: String) throws {
        let arguments = [
            "system",
            "kernel",
            "get",
        ]

        let (data, _, error, status) = try run(arguments: arguments)
        if status != 0 {
            throw CLIError.executionFailed("failed to get kernel: \(error)")
        }

        let kernel = try JSONDecoder().decode(Kernel.self, from: data)
        if kernel.path.lastPathComponent != expectedLastPathComponent {
            throw CLIError.executionFailed("failed to get expected kernel path, got: \(kernel.path.lastPathComponent) expected: \(expectedLastPathComponent)")
        }
    }

    func getArchiveSymlinkTarget(symlinkName: String) throws -> String {
        let archiveReader = try ArchiveReader(file: localTarPath)
        var symlinkTarget = symlinkName
        for (entry, _) in archiveReader {
            if entry.fileType == .symbolicLink && entry.path != nil && entry.path!.hasSuffix(symlinkName) && entry.symlinkTarget != nil {
                symlinkTarget = entry.symlinkTarget!
            }
        }
        return symlinkTarget
    }

    private func getTestName() -> String {
        Test.current!.name.trimmingCharacters(in: ["(", ")"]).lowercased()
    }

    @Test func fromLocalTar() async throws {
        let symlinkBinaryPath: String = URL(filePath: defaultBinaryPath).deletingLastPathComponent().appending(path: "vmlinux.container").relativePath

        try await withTempDir { tempDir in
            // manually download the tar file
            localTarPath = tempDir.appending(path: remoteTar.lastPathComponent)
            try await ContainerAPIClient.FileDownloader.downloadFile(url: remoteTar, to: localTarPath!)
            let symlinkTarget = try getArchiveSymlinkTarget(symlinkName: symlinkBinaryPath)
            let extraArgs: [String] = [
                "--tar",
                localTarPath!.path,
                "--binary",
                symlinkBinaryPath,
            ]

            try doKernelSet(extraArgs: extraArgs)
            try doKernelGet(expectedLastPathComponent: symlinkTarget)
        }
    }

    @Test func fromRemoteTarSymlink() throws {
        // opt/kata/share/kata-containers/vmlinux.container should point to opt/kata/share/kata-containers/vmlinux-<version> in the archive
        let symlinkBinaryPath: String = URL(filePath: defaultBinaryPath).deletingLastPathComponent().appending(path: "vmlinux.container").relativePath
        let symlinkTarget = try getArchiveSymlinkTarget(symlinkName: symlinkBinaryPath)

        let extraArgs: [String] = [
            "--tar",
            defaultKernelTar,
            "--binary",
            symlinkBinaryPath,
        ]

        try doKernelSet(extraArgs: extraArgs)
        try doKernelGet(expectedLastPathComponent: symlinkTarget)
    }

    @Test func fromLocalDisk() async throws {
        try await withTempDir { tempDir in
            // manually download the tar file
            let localTarPath = tempDir.appending(path: remoteTar.lastPathComponent)
            try await ContainerAPIClient.FileDownloader.downloadFile(url: remoteTar, to: localTarPath)
            let symlinkTarget = try getArchiveSymlinkTarget(symlinkName: defaultBinaryPath)

            // extract just the file we want
            let targetPath = tempDir.appending(path: URL(string: defaultBinaryPath)!.lastPathComponent)
            let archiveReader = try ArchiveReader(file: localTarPath)
            let (_, data) = try archiveReader.extractFile(path: defaultBinaryPath)
            try data.write(to: targetPath, options: .atomic)

            let extraArgs = [
                "--binary",
                targetPath.path,
            ]
            try doKernelSet(extraArgs: extraArgs)
            if let url = URL(string: symlinkTarget) {
                let lastPart = url.lastPathComponent
                try doKernelGet(expectedLastPathComponent: lastPart)
                print(lastPart)
            }
        }
    }
}
