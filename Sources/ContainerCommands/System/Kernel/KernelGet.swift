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

import ArgumentParser
import ContainerAPIClient
import ContainerPersistence
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import TerminalProgress

extension Application {
    public struct KernelGet: AsyncLoggableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get the default kernel"
        )

        // @Option(name: .long, help: "The architecture of the kernel binary (values: amd64, arm64)")
        var arch: String = ContainerizationOCI.Platform.current.architecture.description

        @OptionGroup
        public var logOptions: Flags.Logging

        public init() {}

        public func run() async throws {
            let kernel: Kernel = try await ClientKernel.getDefaultKernel(for: self.getSystemPlatform())
            try printValue(kernel)
        }

        private func printValue(_ val: Kernel) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(val)
            print(String(decoding: data, as: UTF8.self))
        }

        private func getSystemPlatform() throws -> SystemPlatform {
            switch arch {
            case "arm64":
                return .linuxArm
            case "amd64":
                return .linuxAmd
            default:
                throw ContainerizationError(.unsupported, message: "unsupported architecture \(arch)")
            }
        }
    }
}
