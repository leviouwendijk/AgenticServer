import Agentic
import AgenticRuntime
import Foundation
import HTTP
import Primitives
import Server

/// A trusted, explicitly configured server-side capability invocation facade.
/// Publication is opt-in per route; it does not change Agent availability or visibility.
public struct CapabilityAPI {
    public let dispatcher: CapabilityDispatcher
    public let authority: BearerAuthority

    public init(
        dispatcher: CapabilityDispatcher,
        authority: BearerAuthority
    ) {
        self.dispatcher = dispatcher
        self.authority = authority
    }

    /// Intended for trusted custom HTTP handlers after their own admission checks.
    /// Only Program and Inference are supported by this first transport slice.
    public func invoke<C: Capability>(
        _ capability: C.Type,
        input: C.Input
    ) async throws -> CapabilityInvocation.Outcome {
        let value = try JSONCoding.default.value(input)
        return try await dispatcher.invoke(
            try CapabilityRoute.invocation(for: C.reference, input: value),
            origin: .host
        )
    }
}

public enum CapabilityRouteError: Error, Sendable {
    case unsupportedKind(CapabilityReference)
    case mismatchedOutcome(CapabilityReference)
}

public enum CapabilityRoute {
    /// Stable, transport-safe response. Does not publish raw checkpoint,
    /// internal execution trace, credentials, or approval records.
    public struct Response: Returnable {
        public let status: String
        public let output: JSONValue?

        public init(status: String, output: JSONValue?) {
            self.status = status
            self.output = output
        }
    }

    public struct Request: Requestable {
        public let input: JSONValue

        public init(input: JSONValue) {
            self.input = input
        }
    }

    /// The first slice supports installed Program and Inference capabilities.
    /// Unsupported kinds fail closed, not as privileged host tool/agent calls.
    public static func invocation(
        for reference: CapabilityReference,
        input: JSONValue
    ) throws -> CapabilityInvocation {
        switch reference {
        case .program(let identifier):
            return .program(identifier: identifier, input: input, realization: nil)
        case .inference(let identifier):
            return .inference(identifier: identifier, input: input, realization: nil)
        case .tool, .agent:
            throw CapabilityRouteError.unsupportedKind(reference)
        }
    }

    public static func make<C: Capability>(
        _ endpoint: HTTPEndpoint,
        capability _: C.Type,
        using api: CapabilityAPI
    ) -> Route {
        let dispatcher = api.dispatcher
        let reference = C.reference
        return Route.typed(
            endpoint,
            request: Request.self
        ) { request, _ in
            // Validate the incoming JSON against the actual typed input model.
            _ = try JSONCoding.default.decode(C.Input.self, from: request.input)
            let invocation = try invocation(for: reference, input: request.input)
            let outcome = try await dispatcher.invoke(invocation, origin: .host)
            switch outcome {
            case .program(let record):
                guard case .program = reference else {
                    throw CapabilityRouteError.mismatchedOutcome(reference)
                }
                return Response(status: record.outcome.rawValue, output: record.output)
            case .inference(let result):
                guard case .inference = reference else {
                    throw CapabilityRouteError.mismatchedOutcome(reference)
                }
                let output = try JSONDecoder().decode(JSONValue.self, from: result.output)
                return Response(status: "succeeded", output: output)
            case .tool, .agent:
                throw CapabilityRouteError.mismatchedOutcome(reference)
            }
        }
        .use(BearerAuthorityMiddleware(authority: api.authority))
    }
}

/// Primary endpoint-first API; shares the same route-construction engine.
public func route<C: Capability>(
    _ endpoint: HTTPEndpoint,
    capability: C.Type,
    using api: CapabilityAPI
) -> Route {
    CapabilityRoute.make(endpoint, capability: capability, using: api)
}

/// Server-style verb convenience, not a separate implementation.
public func post<C: Capability>(
    _ path: String,
    capability: C.Type,
    using api: CapabilityAPI
) -> Route {
    route(
        HTTPEndpoint(method: .post, path: path),
        capability: capability,
        using: api
    )
}
