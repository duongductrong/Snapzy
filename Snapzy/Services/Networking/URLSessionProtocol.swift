//
//  URLSessionProtocol.swift
//  Snapzy
//
//  Protocol abstraction for URLSession to enable test injection.
//

import Foundation

protocol URLSessionProtocol: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}
