import Darwin
import Foundation
import TranslexCore

let arguments = Array(CommandLine.arguments.dropFirst())
let path = ProcessInfo.processInfo.environment["TRANSLEX_DB_PATH"] ?? DatabaseStore.defaultPath
let needsStdin = arguments.starts(with: ["lexeme", "upsert"]) ||
    arguments.starts(with: ["queue", "complete"])
let stdin = needsStdin ? FileHandle.standardInput.readDataToEndOfFile() : nil

do {
    let store = try DatabaseStore(path: path)
    let result = try AgentCLI(store: store).execute(arguments: arguments, stdin: stdin)
    FileHandle.standardOutput.write(Data(result.stdout.utf8))
    exit(result.exitCode)
} catch let error as AgentCLIError {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    switch error {
    case .usage: exit(64)
    case .invalidInput: exit(65)
    case .notFound: exit(66)
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
