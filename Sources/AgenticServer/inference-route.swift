import Agentic
import AgenticRuntime
import Foundation
import HTTP
import Primitives
import Server

/// Publishes one installed inference through a bearer-protected, JSON endpoint.
/// The caller can supply inference input, but cannot select the inference,
/// model, realization, executor, or underlying credentials.
public enum InferenceRoute {
    public struct Request: Requestable {
        public let input: JSONValue

        public init(input: JSONValue) {
            self.input = input
        }
    }

    public struct Response: Returnable {
        public let output: JSONValue

        public init(output: JSONValue) {
            self.output = output
        }
    }

    public static func make(
        path: String,
        identifiedBy identifier: InferenceIdentifier,
        runtime: AgenticRuntime,
        executor: any InferenceExecuting,
        authority: BearerAuthority
    ) -> Route {
        Route.typed(
            HTTPEndpoint(method: .post, path: path),
            request: Request.self
        ) { request, _ in
            let invocation = try await runtime.executeInference(
                identifiedBy: identifier,
                input: request.input,
                using: executor
            )

            let output = try JSONDecoder().decode(
                JSONValue.self,
                from: invocation.output
            )

            return Response(output: output)
        }
        .use(BearerAuthorityMiddleware(authority: authority))
    }
}
