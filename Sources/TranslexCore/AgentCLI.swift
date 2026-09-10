import Foundation

public struct AgentCLIResult: Equatable, Sendable {
    public let stdout: String
    public let exitCode: Int32

    public init(stdout: String, exitCode: Int32 = 0) {
        self.stdout = stdout
        self.exitCode = exitCode
    }
}

public enum AgentCLIError: Error, LocalizedError, Equatable {
    case usage(String)
    case invalidInput(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let value), .invalidInput(let value), .notFound(let value): value
        }
    }
}

public final class AgentCLI: @unchecked Sendable {
    private let store: DatabaseStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(store: DatabaseStore) {
        self.store = store
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func execute(arguments: [String], stdin: Data?) throws -> AgentCLIResult {
        guard let group = arguments.first else {
            throw AgentCLIError.usage(Self.usage)
        }
        switch group {
        case "queue":
            return try queue(Array(arguments.dropFirst()), stdin: stdin)
        case "lexeme":
            return try lexeme(Array(arguments.dropFirst()), stdin: stdin)
        case "db":
            return try database(Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            return .init(stdout: Self.usage + "\n")
        default:
            throw AgentCLIError.usage("Unknown command: \(group)\n\(Self.usage)")
        }
    }

    private func queue(_ arguments: [String], stdin: Data?) throws -> AgentCLIResult {
        guard let command = arguments.first else {
            throw AgentCLIError.usage("Usage: translex queue <list|claim|complete|fail>")
        }
        switch command {
        case "list":
            let status: QueueStatus?
            if arguments.count > 1 {
                guard let parsed = QueueStatus(rawValue: arguments[1]) else {
                    throw AgentCLIError.invalidInput("Invalid queue status: \(arguments[1])")
                }
                status = parsed
            } else {
                status = nil
            }
            return try json(store.listQueue(status: status))
        case "claim":
            guard arguments.count == 1 else {
                throw AgentCLIError.usage("Usage: translex queue claim")
            }
            return try json(store.claimNext())
        case "complete":
            guard arguments.count == 2 else {
                throw AgentCLIError.usage("Usage: translex queue complete <id> < lexeme.json")
            }
            let payload = try decodeLexeme(stdin)
            try store.completeQueueItem(id: arguments[1], lexeme: payload)
            return ok(message: "completed", id: arguments[1])
        case "fail":
            guard arguments.count >= 3 else {
                throw AgentCLIError.usage("Usage: translex queue fail <id> <message> [--retry]")
            }
            let retry = arguments.contains("--retry")
            let messageParts = arguments.dropFirst(2).filter { $0 != "--retry" }
            let message = messageParts.joined(separator: " ")
            guard !message.isEmpty else {
                throw AgentCLIError.invalidInput("Failure message must not be empty.")
            }
            try store.failQueueItem(id: arguments[1], error: message, retry: retry)
            return ok(message: retry ? "requeued" : "failed", id: arguments[1])
        default:
            throw AgentCLIError.usage("Unknown queue command: \(command)")
        }
    }

    private func lexeme(_ arguments: [String], stdin: Data?) throws -> AgentCLIResult {
        guard let command = arguments.first else {
            throw AgentCLIError.usage("Usage: translex lexeme <get|upsert>")
        }
        switch command {
        case "get":
            guard arguments.count >= 3,
                  let language = SupportedLanguage(rawValue: arguments[1]) else {
                throw AgentCLIError.usage("Usage: translex lexeme get <en|vi> <lemma>")
            }
            let lemma = arguments.dropFirst(2).joined(separator: " ")
            guard let record = try store.getLexeme(
                language: language,
                normalizedLemma: lemma
            ) else {
                throw AgentCLIError.notFound("Lexeme not found.")
            }
            return try json(record)
        case "upsert":
            guard arguments.count == 1 else {
                throw AgentCLIError.usage("Usage: translex lexeme upsert < lexeme.json")
            }
            let payload = try decodeLexeme(stdin)
            try store.upsertLexeme(payload)
            return ok(message: "upserted", id: nil)
        default:
            throw AgentCLIError.usage("Unknown lexeme command: \(command)")
        }
    }

    private func database(_ arguments: [String]) throws -> AgentCLIResult {
        guard arguments == ["validate"] else {
            throw AgentCLIError.usage("Usage: translex db validate")
        }
        return try json(store.validateDatabase())
    }

    private func decodeLexeme(_ data: Data?) throws -> LexemeInput {
        guard let data, !data.isEmpty else {
            throw AgentCLIError.invalidInput("Lexeme JSON is required on stdin.")
        }
        do {
            let value = try decoder.decode(LexemeInput.self, from: data)
            try LexicalValidator.validate(value)
            return value
        } catch let error as AgentCLIError {
            throw error
        } catch {
            throw AgentCLIError.invalidInput("Invalid lexeme payload: \(error.localizedDescription)")
        }
    }

    private func json<T: Encodable>(_ value: T) throws -> AgentCLIResult {
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AgentCLIError.invalidInput("Unable to encode command result.")
        }
        return .init(stdout: text + "\n")
    }

    private func ok(message: String, id: String?) -> AgentCLIResult {
        struct Payload: Encodable {
            let id: String?
            let message: String
            let ok: Bool
        }
        return try! json(Payload(id: id, message: message, ok: true))
    }

    public static let usage = """
    Usage:
      translex queue list [pending|processing|ready|failed]
      translex queue claim
      translex queue complete <id> < lexeme.json
      translex queue fail <id> <message> [--retry]
      translex lexeme get <en|vi> <lemma>
      translex lexeme upsert < lexeme.json
      translex db validate
    """
}
