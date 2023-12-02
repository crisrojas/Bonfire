//
//  Bonfire.swift
//  Bonfire
//
//  Created by Cristian Felipe Patiño Rojas on 02/12/2023.
//

import Foundation

//
//  Bonfire.swift
//  Networking
//
//  Created by Cristian Felipe Patiño Rojas on 02/12/2023.
//

import Combine

// https://github.com/jimlai586/Bonfire/blob/master/README.md
protocol Service {
    static var mods: [String: (inout URLRequest) -> Void] {get set}
    var baseURL: String {get set}
    func config(_ pat: String, _ mod: @escaping (inout URLRequest) -> Void)
    func decorated(_ absURL: String, _ req: URLRequest) -> URLRequest
    func match(_ pat: String, _ absURL: String) -> Bool
    func makeRequest(_ relativeURL: String) -> URLRequest
}

extension Service {
    func config(_ pat: String, _ mod: @escaping (inout URLRequest) -> Void) {
        Self.mods[pat] = mod
    }
    func decorated(_ absURL: String, _ req: URLRequest) -> URLRequest {
        Array(Self.mods.keys).reduce(into: req) { (result, pat) in
            guard match(pat, absURL), let mod = Self.mods[pat] else {return}
            mod(&result)
        }
    }
    func match(_ pat: String, _ absURL: String) -> Bool {
        true
    }

    func makeRequest(_ relativeURL: String) -> URLRequest {
        let absURL = baseURL + relativeURL
        return URLRequest(url: URL(string: absURL)!)
    }
}


public final class API: Service {
    static var mods = [String : (inout URLRequest) -> Void]()
    var baseURL = "https://crisrojas.github.io/dummyjson/api/v1/"
    let employees = EmployeesResource()
    let employeesCodable = EmployeesCodableResource()
}

enum HttpMethod: String {
    case get, post, put, delete
}

protocol HttpBody {
    var body: Data? {get}
}

protocol NetData {
//    init()
    static func decode(_ data: Data) -> Self?
}

typealias Request<T> = AnyPublisher<(T, HTTPURLResponse), Error>

/// @question: What if we need some other actions for a resource ? POST/PUT/PATCH
///  Use the load(using:) method:
final class TodoResource: Resource {
    var cancellable: AnyCancellable?
    static var mods = [String : (Request<MJ>) -> Request<MJ>]()
    var url: String = "test"
    var error: Error?
    var response: HTTPURLResponse?
    var contentType = "application/json"

    @Published var data = MJ.raw("data")
}

let todos = TodoResource()
struct TodoPOST: HttpBody, Encodable {
    let title: String
    let notes: String
    var isChecked = false
    var body: Data? { try? JSONEncoder().encode(self) }
}

let postRequest = todos.request(.post, TodoPOST(title: "Buy apples", notes: "freaking love 🍎s"))
let POST = todos.load(using: postRequest)

protocol Resource: ObservableObject {
    associatedtype ResourceType: NetData
    static var mods: [String: (Request<ResourceType>) -> Request<ResourceType>] {get set}
    static var service: Service {get}
    var cancellable: AnyCancellable? {get set}
    var url: String {get set}
    var data: ResourceType {get set}
    var error: Error? {get set}
    var response: HTTPURLResponse? {get set}
    var urlRequestBase: URLRequest {get}
    var contentType: String {get}
    func load() -> Callback<ResourceType>
    func load(using: Request<ResourceType>) -> Callback<ResourceType>
    func request(_ method: HttpMethod, _ payload: HttpBody?) -> Request<ResourceType>
    func config(_ pat: String, _ mod: @escaping (Request<ResourceType>) -> Request<ResourceType>)
    func chained(_ req: Request<ResourceType>) -> Request<ResourceType>
}

extension Resource {
    
    /// @question: Why having a default value for this?
    /// If we want to move this logic to a common reusable library, wouldn't that mean that the Resource is coupled to a concrete implementation?
    /// Nope -> I think this static can be removed if moved in a library and added on the importer module through protocol extension.
    /// Still, that would make the Resource only work with a data api, if we have more than one api in the app I believe we should modifiy this to not be a static
    /// so it can be passed to a given resource on instantiation/configuration (through property override)
    static var service: Service {
        API()
    }
    var urlRequestBase: URLRequest {
        var r = Self.service.makeRequest(url)
        r.addValue(contentType, forHTTPHeaderField: "Content-Type")
        return r
    }
    
    func request(_ method: HttpMethod = .post, _ payload: HttpBody? = nil) -> Request<ResourceType> {
        var r = urlRequestBase
        r.httpMethod = method.rawValue.capitalized
        r.httpBody = payload?.body
        
        /// @question: Example usage of mods appended through the decorated method on service?
        let req = Self.service.decorated(r.url?.absoluteString ?? "",  r)
        return URLSession.shared.dataTaskPublisher(for: req).tryMap {
            (data, response) in
            guard let resp = response as? HTTPURLResponse, 200 ..< 300 ~= resp.statusCode else {
                throw NetError.errorResponse
            }
            
            /// @question: Why not using decodable directly ?
            /// Guess we use NetData protocol so we can have the flexibility for use MagicJSON if wanted
            guard let d = ResourceType.decode(data) else {
                throw NetError.decodeError
            }
            return (d, resp)
        }.eraseToAnyPublisher()
    }
    
    @discardableResult
    func load(using req: Request<ResourceType>) -> Callback<ResourceType> {
        let cb = Callback<ResourceType>()
        cancellable = req.receive(on: RunLoop.main).sink(receiveCompletion: { (completion) in
            switch completion {
            case .finished:
                cb.completion?()
            case .failure(let e):
                self.error = e
                cb.failure?(e)
            }
        }) { (data, resp) in
            self.data = data
            self.response = resp
            cb.success?(data)
        }
        return cb
    }
    @discardableResult
    public func load() -> Callback<ResourceType> {
        load(using: request(.get))
    }
    func config(_ pat: String, _ mod: @escaping (Request<ResourceType>) -> Request<ResourceType>) {
        Self.mods[pat] = mod
    }
    func chained(_ req: Request<ResourceType>) -> Request<ResourceType> {
        req
    }
}

/// @question: couldn't we just have two callbacks:
/// onSuccess & onFailure and return Self so we can handle both cases?
/// Something like
/// myResource.load().onSucesss { _ in }.onFailure { print("failed") }
/// Isn't that necessary to handle both cases?
/// Or maybe we could just have the state in resource itself published so view can listen and act,
/// that way we could havbe only the "completiion" callback and remove the onSuccess & onFailure ones
final class Callback<T> {
    var completion: (() -> Void)?
    var success: ((T) -> Void)?
    var failure: ((Error) -> Void)?
    func onCompletion(_ cls: @escaping () -> Void) {
        completion = cls
    }
    func onSuccess(_ cls: @escaping (T) -> Void) {
        success = cls
    }
    func onFailure(_ cls: @escaping (Error) -> Void) {
        failure = cls
    }
}

enum NetError: Error {
    case errorResponse, decodeError
}


struct Wrapper<T: Decodable>: Decodable,  NetData {
    var data: [T]?
}

typealias AppRequest<T: Decodable> = Request<Wrapper<T>>

fileprivate var jsonDecoder: JSONDecoder = {
  let d = JSONDecoder()
//    d.keyDecodingStrategy = .convertFromSnakeCase // wont working because we aren't mapping to "name" instead of "employeeName".
    return d
}()

extension Decodable {
    static func decode(_ data: Data) -> Self? {
        try? jsonDecoder.decode(Self.self, from: data)
    }
}

public final class EmployeesCodableResource: Resource {
    var cancellable: AnyCancellable?
    static var mods = [String : (AppRequest<Employee>) -> AppRequest<Employee>]()
    var url: String = "employees"
    var error: Error?
    var response: HTTPURLResponse?
    var contentType = "application/json"

    @Published var data = Wrapper<Employee>()
    var employes: [Employee] {data.data ?? []}
}

public final class EmployeesResource: Resource {
    var cancellable: AnyCancellable?
    static var mods = [String : (Request<MJ>) -> Request<MJ>]()
    var url: String = "employees"
    var error: Error?
    var response: HTTPURLResponse?
    var contentType = "application/json"

    @Published var data = MJ.raw("data")
    private var container: [MJ] {data[P.data].arrayValue}
    
    var list: [(id: Int, name: String)] {
        container.map {
            (id: $0[EK.id].intValue, name: $0[EK.name].stringValue)
        }
    }
    
    /// Testing this so we can use it on swiftui
    var listBis: [Int:MJ] {
        Dictionary(uniqueKeysWithValues: container.map { ($0[EK.id].intValue, $0) })
    }
}

extension Dictionary {
    func tuples() -> [(id: Key, value: Value)] {
        map { (id: $0.key, value: $0.value)}
    }
}

typealias P = Params
enum Params: String, JSONKey {
    var jkey: String { self.rawValue }
    case data
}

typealias EK = EmployeeKeys
enum EmployeeKeys: String, JSONKey {
    var jkey: String { self.rawValue }
    case id
    case name   = "employee_name"
    case age    = "employee_age"
    case salary = "employee_salary"
}

public protocol JSONKey {
    var jkey: String {get}
}

public protocol MJConvertible {
    var mj: MagicJSON {get}
}

extension String: JSONKey {
    public var jkey: String {
        return self
    }
}

public protocol Initable {
    init()
}

extension Dictionary: MJConvertible where Key: JSONKey {
    public var mj: MagicJSON {
        return .dict(self.toStringKey())
    }
}

public protocol HashableJSONKey {
    func toStringKey() -> [String: Any]
}

extension Dictionary: HashableJSONKey where Key: JSONKey {
    public func toStringKey() -> [String: Any] {
        var d = [String: Any]()
        var nd: [Key: Any?] = self
        nd = nd.mapValues { v in
            guard let v = v else {
                return MJ.nullString
            }
            return v
        }
        for k in nd.keys {
            let v = nd[k]!
            let s = k.jkey
            switch v {
            case let u as [Key: Any?]:
                d[s] = u.toStringKey()
            default:
                d[s] = v
            }
        }
        return d
    }
}

// https://github.com/jimlai586/MagicJSON
public typealias MJ = MagicJSON
public enum MagicJSON {
    public static var nullString = "null"
    case arr([Any]), dict([String: Any]), empty, null, raw(Any)
}

extension MagicJSON: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Any
    public init(arrayLiteral elements: ArrayLiteralElement...) {
        self.init(elements)
    }
}

extension MagicJSON: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

extension MagicJSON: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = Int
    public init(integerLiteral value: IntegerLiteralType) {
        self.init(value)
    }
}

extension MagicJSON: ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Double
    public init(floatLiteral value: FloatLiteralType) {
        self.init(value)
    }
}

extension MagicJSON: ExpressibleByBooleanLiteral {
    public typealias BooleanLiteralType = Bool
    public init(booleanLiteral value: BooleanLiteralType) {
        self.init(value)
    }
}

public extension MagicJSON {
    init(_ jd: Any?) {
        guard let jd = jd else {
            self = .null
            return
        }
        switch jd {
        case let u as [Any]:
            self = .arr(u)
        case let u as [String: Any]:
            self = .dict(u.toStringKey())
        case let u as HashableJSONKey:
            self = .dict(u.toStringKey())
        case let u as MJ:
            self = u
        default:
            self = .raw(jd)
        }
    }
    init() {
        self = .empty
    }
    init(data: Data) {
        let json = try? JSONSerialization.jsonObject(with: data, options: [])
        self.init(json)
    }
    subscript<T>(_ k: T) -> MagicJSON where T: JSONKey {
        get {
            switch self {
            case .dict(let d):
                return MagicJSON(d[k.jkey])
            default:
                return MagicJSON.null
            }
        }
        set {
            switch self {
            case .dict(var d):
                if case .null = newValue {
                    d[k.jkey] = nil
                } else {
                    d[k.jkey] = newValue
                }
                self = .dict(d)
            default:
                break
            }
        }
    }
    subscript(_ idx: Int) -> MagicJSON {
        get {
            switch self {
            case .arr(let arr):
                guard 0 ..< arr.count ~= idx else {
                    return MagicJSON.null
                }
                return MagicJSON(arr[idx])
            default:
                return MagicJSON.null
            }
        }
        set {
            switch self {
            case .arr(var arr):
                guard 0 ..< arr.count ~= idx else {
                    return
                }
                arr[idx] = newValue
                self = .arr(arr)
            default:
                break
            }
        }
    }

    var stringValue: String {
        switch self {
        case .raw(let u):
            return u as? String ?? String(describing: u)
        default:
            return ""
        }
    }
    var intValue: Int {
        switch self {
        case .raw(let u):
            return u as? Int ?? 0
        default:
            return 0
        }
    }
    var floatValue: Float {
        switch self {
        case .raw(let u):
            return u as? Float ?? 0
        default:
            return 0
        }
    }
    var doubleValue: Double {
        switch self {
        case .raw(let u):
            return u as? Double ?? 0
        default:
            return 0
        }
    }
    var string: String? {
        switch self {
        case .raw(let u):
            return String(describing: u)
        default:
            return nil
        }
    }
    var int: Int? {
        switch self {
        case .raw(let u):
            return u as? Int
        default:
            return nil
        }
    }
    var float: Float? {
        switch self {
        case .raw(let u):
            return u as? Float
        default:
            return nil
        }
    }
    var double: Double? {
        switch self {
        case .raw(let u):
            return u as? Double
        default:
            return nil
        }
    }
    var arrayValue: [MagicJSON] {
        switch self {
        case .arr(let u):
            return u.map {MagicJSON($0)}
        default:
            return []
        }
    }
    var dictValue: [String: MagicJSON] {
        switch self {
        case .dict(let u):
            return u.mapValues {MagicJSON($0)}
        default:
            return [:]
        }
    }
    var data: Data? {
        return try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
    }
    var jsonObject: Any {
        switch self {
        case .arr(let a):
            return a.map { MJ($0).jsonObject}
        case .dict(let d):
            return d.mapValues {MJ($0).jsonObject}
        case .raw(let r):
            return r
        case .null:
            return MJ.nullString
        default:
            return [String: String]()
        }
    }
    func val<T>() -> T where T: Initable {
        switch self {
        case .raw(let v):
            return v as? T ?? T()
        default:
            return T()
        }
    }
    func optional<T>() -> T? {
        switch self {
        case .raw(let v):
            return v as? T
        default:
            return nil
        }
    }
}

extension MagicJSON: CustomStringConvertible {
    public var description: String {
        switch self {
        case .arr(let a):
            return String(describing: a)
        case .dict(let d):
            return String(describing: d)
        case .empty:
            return "empty"
        case .null:
            return MJ.nullString
        case .raw(let u):
            return String(describing: u)
        }
    }
}


extension MJ: HttpBody, NetData {
    static func decode(_ data: Data) -> MJ? {
        MJ(data: data)
    }

    var body: Data? {
        self.data
    }
}


public struct Employee: Decodable, Identifiable {
    public let id: Int
    let name: String
    let age: Int
    let salary: Int
}

extension Employee {
    enum CodingKeys: String, CodingKey {
        case id
        case name   = "employee_name"
        case age    = "employee_age"
        case salary = "employee_salary"
    }
}

import SwiftUI
extension [Employee]: View {
    public var body: some View {
        List(self) { item in
            NavigationLink {
                item
            } label: {
                item.name
            }

        }
    }
}

extension Employee: View {
    public var body: some View {
        VStack {
            HStack {
                "Name: " + name
            }
            HStack {
                "Age: ".body + age.body
            }
            HStack {
                "Salary: ".body + salary.body
            }
        }
    }
}
