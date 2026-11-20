import Agentic
import AgenticRuntime
import AgenticServer
import Foundation
import HTTP
import Primitives
import Server

private enum FixtureInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.agenticserver.inference",
        purpose: "Verify typed HTTP inference dispatch."
    )
}

private struct FixtureProgram: Program {
    typealias Input = String
    typealias Output = String

    static let definition = ProgramDefinition(
        identifier: "fixture.agenticserver.program",
        purpose: "Verify typed HTTP program dispatch."
    )

    func run(_ input: String, in _: ProgramContext) async throws -> String {
        input.uppercased()
    }
}

private struct FixtureInferenceExecutor: InferenceExecuting {
    func execute(
        _ invocation: InferenceInvocation
    ) async throws -> InferenceInvocation.Response {
        let input = try JSONDecoder().decode(String.self, from: invocation.input)
        return .init(
            output: try JSONEncoder().encode("inferred:\(input)"),
            record: .init(
                inference: invocation.definition.identifier,
                strategy: invocation.realization.strategy
            )
        )
    }
}

@main
struct AgenticServerTestFlows {
    static func main() async throws {
        let realization = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "Deterministic fixture.",
            budget: .singleAttempt
        )
        let application = Agentic.application("fixture.agenticserver.http") {
            install(FixtureInference.self, realization: realization)
            install(FixtureProgram())
        }
        let runtime = try await AgenticRuntime(application: application)
        let state = AgentCapabilityState(installed: runtime.installed.capabilities)
        let dispatcher = CapabilityDispatcher(
            runtime: runtime,
            capabilityState: state,
            services: RuntimeServices(
                program: .init(inference: FixtureInferenceExecutor())
            )
        )
        let authority = try BearerAuthority(
            authorized_tokens: ["fixture-token"]
        )
        let api = CapabilityAPI(dispatcher: dispatcher, authority: authority)
        let router = Router(routes: [
            post("/fixture/inference", capability: FixtureInference.self, using: api),
            post("/fixture/program", capability: FixtureProgram.self, using: api),
        ])

        func request(_ path: String, _ input: String, token: String? = "fixture-token") -> HTTPRequest {
            var headers = ["Content-Type": "application/json"]
            if let token {
                headers["Authorization"] = "Bearer \(token)"
            }
            return HTTPRequest(
                method: .post,
                path: path,
                headers: headers,
                body: "{\"input\":\(input)}"
            )
        }

        let noToken = await router.route(
            request("/fixture/inference", "\"hello\"", token: nil)
        )
        precondition(noToken.status.code == 401, "Missing bearer token must reject")

        let badToken = await router.route(
            request("/fixture/inference", "\"hello\"", token: "wrong")
        )
        precondition(badToken.status.code == 401, "Invalid bearer token must reject")

        let invalidInput = await router.route(
            request("/fixture/inference", "123")
        )
        precondition(invalidInput.status.code == 400, "Typed input mismatch: expected HTTP 400, received HTTP \(invalidInput.status.code); body=\(invalidInput.body)")

        let inference = await router.route(
            request("/fixture/inference", "\"hello\"")
        )
        precondition(inference.status.code == 200, "Inference must succeed")
        precondition(inference.body.contains("inferred:hello"), "Inference output must round-trip")

        let program = await router.route(
            request("/fixture/program", "\"hello\"")
        )
        precondition(program.status.code == 200, "Program must succeed")
        precondition(program.body.contains("HELLO"), "Program output must round-trip")

        do {
            _ = try CapabilityRoute.invocation(
                for: .tool(ToolIdentifier(rawValue: "fixture.unsupported")),
                input: .string("hello")
            )
            preconditionFailure("Tool HTTP invocation must fail closed")
        } catch CapabilityRouteError.unsupportedKind {
            // Expected.
        }

        print("AgenticServer typed capability routing: 6 checks passed")
    }
}
