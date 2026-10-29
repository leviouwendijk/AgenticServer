import Agentic
import AgenticRuntime
import Foundation
import HTTP
import Primitives
import Server

/// A trusted, explicitly configured server-side capability invocation facade.
/// Publication is opt-in per route; it does not change Agent availability or visibility.
public struct CapabilityAPI: Sendable {
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

        /// The transport status is derived from the execution outcome; the
        /// returned JSON envelope contains no checkpoint or internal trace.
        /// HTTPRespondable requires response(status:); Route.typed calls the
        /// protocol's no-argument convenience, which delegates here.
        public func response(status _: HTTPStatus) throws -> HTTPResponse {
            let mappedStatus: HTTPStatus
            switch status {
            case "succeeded":
                mappedStatus = .ok
            case "suspended":
                mappedStatus = .accepted
            case "failed":
                mappedStatus = .internalServerError
            case "invalid_input":
                mappedStatus = .badRequest
            default:
                mappedStatus = .internalServerError
            }
            // The two-argument Returnable helper performs JSON serialization.
            // This is NOT the HTTPRespondable witness, so it cannot recurse.
            return try response(
                status: mappedStatus,
                using: HTTPJSONCoding.current.encoder()
            )
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

    /// Translate native outcomes without exposing internal records or checkpoints.
    /// A successful response must satisfy the selected capability's output type.
    public static func respond<C: Capability>(
        to outcome: CapabilityInvocation.Outcome,
        reference: CapabilityReference,
        capability _: C.Type
    ) throws -> Response {
        guard reference == C.reference else {
            throw CapabilityRouteError.mismatchedOutcome(reference)
        }
        switch outcome {
        case .program(let record):
            guard case .program = reference else {
                throw CapabilityRouteError.mismatchedOutcome(reference)
            }
            guard case .program(let identifier) = reference,
                  record.programIdentifier == identifier else {
                throw CapabilityRouteError.mismatchedOutcome(reference)
            }
            switch record.outcome {
            case .succeeded:
                guard let output = record.output else {
                    throw CapabilityRouteError.mismatchedOutcome(reference)
                }
                _ = try JSONCoding.default.decode(C.Output.self, from: output)
                return Response(status: "succeeded", output: output)
            case .suspended:
                return Response(status: "suspended", output: nil)
            case .failed:
                return Response(status: "failed", output: nil)
            }
        case .inference(let result):
            guard case .inference = reference else {
                throw CapabilityRouteError.mismatchedOutcome(reference)
            }
            guard case .inference(let identifier) = reference,
                  result.record.inference == identifier else {
                throw CapabilityRouteError.mismatchedOutcome(reference)
            }
            let output = try JSONDecoder().decode(JSONValue.self, from: result.output)
            _ = try JSONCoding.default.decode(C.Output.self, from: output)
            return Response(status: "succeeded", output: output)
        case .tool, .agent:
            throw CapabilityRouteError.mismatchedOutcome(reference)
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
        ) { request, _ -> Response in
            // Input decoding is client validation, not an internal execution failure.
            let typedInput: C.Input
            do {
                typedInput = try JSONCoding.default.decode(
                    C.Input.self,
                    from: request.input
                )
            } catch {
                return Response(status: "invalid_input", output: nil)
            }

            // Dispatch the successfully decoded typed value, not unchecked wire JSON.
            let input = try JSONCoding.default.value(typedInput)
            let invocation = try invocation(for: reference, input: input)
            let outcome = try await dispatcher.invoke(invocation, origin: .host)
            return try respond(to: outcome, reference: reference, capability: C.self)
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
