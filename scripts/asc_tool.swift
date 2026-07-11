// Minimal App Store Connect API client for provisioning automation.
// Auth: ES256 JWT signed with the .p8 key (via CryptoKit).
// Reads ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER from the environment.
//
// Subcommands:
//   test                                   verify auth (lists a few devices)
//   devices                                print "id<TAB>udid<TAB>name" for iOS devices
//   register <udid> <name>                 register an iOS device
//   bundle <identifier> <name>             ensure a bundle id, print its resource id
//   cert <TYPE> <csrPath> <outDER>         create a cert, write DER, print resource id
//   adhoc <bundleResId> <certResId> <out>  create IOS_APP_ADHOC profile -> write .mobileprovision
import Foundation
import CryptoKit

let env = ProcessInfo.processInfo.environment
guard let keyPath = env["ASC_KEY_PATH"], let keyId = env["ASC_KEY_ID"], let issuer = env["ASC_ISSUER"] else {
    FileHandle.standardError.write(Data("missing ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER\n".utf8)); exit(2)
}
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { FileHandle.standardError.write(Data("no command\n".utf8)); exit(2) }

func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func makeJWT() -> String {
    let pem = (try? String(contentsOfFile: keyPath, encoding: .utf8)) ?? ""
    let key = try! P256.Signing.PrivateKey(pemRepresentation: pem)
    let header = #"{"alg":"ES256","kid":"\#(keyId)","typ":"JWT"}"#
    let now = Int(Date().timeIntervalSince1970)
    let payload = #"{"iss":"\#(issuer)","iat":\#(now),"exp":\#(now + 1000),"aud":"appstoreconnect-v1"}"#
    let signingInput = b64url(Data(header.utf8)) + "." + b64url(Data(payload.utf8))
    let sig = try! key.signature(for: Data(signingInput.utf8))
    return signingInput + "." + b64url(sig.rawRepresentation)
}

func api(_ method: String, _ path: String, body: [String: Any]? = nil) -> (Int, [String: Any]) {
    var req = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com\(path)")!)
    req.httpMethod = method
    req.setValue("Bearer \(makeJWT())", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body { req.httpBody = try! JSONSerialization.data(withJSONObject: body) }
    let sem = DispatchSemaphore(value: 0)
    var status = 0; var json: [String: Any] = [:]
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { json = obj }
        sem.signal()
    }.resume()
    sem.wait()
    return (status, json)
}

func fail(_ msg: String, _ json: [String: Any]) -> Never {
    FileHandle.standardError.write(Data("\(msg): \(json)\n".utf8)); exit(1)
}

switch cmd {
case "test":
    let (s, j) = api("GET", "/v1/devices?limit=3")
    if s == 200 {
        let data = (j["data"] as? [[String: Any]]) ?? []
        print("OK — auth works. \(data.count) device(s) sample returned (total may be more).")
    } else { fail("auth failed (HTTP \(s))", j) }

case "devices":
    let (s, j) = api("GET", "/v1/devices?limit=200&filter[platform]=IOS")
    if s != 200 { fail("list devices failed (\(s))", j) }
    for d in (j["data"] as? [[String: Any]]) ?? [] {
        let id = d["id"] as? String ?? ""
        let a = d["attributes"] as? [String: Any] ?? [:]
        print("\(id)\t\(a["udid"] as? String ?? "")\t\(a["name"] as? String ?? "")\t\(a["status"] as? String ?? "")")
    }

case "register":
    guard args.count >= 3 else { fail("register <udid> <name>", [:]) }
    let body: [String: Any] = ["data": ["type": "devices",
        "attributes": ["name": args[2], "udid": args[1], "platform": "IOS"]]]
    let (s, j) = api("POST", "/v1/devices", body: body)
    if s == 201 || s == 200 { print((j["data"] as? [String: Any])?["id"] as? String ?? "") }
    else { fail("register failed (\(s))", j) }

case "bundle":
    guard args.count >= 3 else { fail("bundle <identifier> <name>", [:]) }
    let ident = args[1]
    let (s, j) = api("GET", "/v1/bundleIds?filter[identifier]=\(ident)")
    if s == 200, let arr = j["data"] as? [[String: Any]], let first = arr.first {
        print(first["id"] as? String ?? ""); break
    }
    let body: [String: Any] = ["data": ["type": "bundleIds",
        "attributes": ["identifier": ident, "name": args[2], "platform": "IOS"]]]
    let (s2, j2) = api("POST", "/v1/bundleIds", body: body)
    if s2 == 201 { print((j2["data"] as? [String: Any])?["id"] as? String ?? "") }
    else { fail("create bundle failed (\(s2))", j2) }

case "cert":
    guard args.count >= 4 else { fail("cert <TYPE> <csrPath> <outDER>", [:]) }
    let csr = (try? String(contentsOfFile: args[2], encoding: .utf8)) ?? ""
    let body: [String: Any] = ["data": ["type": "certificates",
        "attributes": ["certificateType": args[1], "csrContent": csr]]]
    let (s, j) = api("POST", "/v1/certificates", body: body)
    guard s == 201, let d = j["data"] as? [String: Any],
          let a = d["attributes"] as? [String: Any],
          let content = a["certificateContent"] as? String,
          let der = Data(base64Encoded: content) else { fail("create cert failed (\(s))", j) }
    try! der.write(to: URL(fileURLWithPath: args[3]))
    print(d["id"] as? String ?? "")

case "adhoc":
    guard args.count >= 4 else { fail("adhoc <bundleResId> <certResId> <out> [deviceIds...]", [:]) }
    let bundleId = args[1], certId = args[2], out = args[3]
    var deviceIds = Array(args.dropFirst(4))
    if deviceIds.isEmpty {
        let (s, j) = api("GET", "/v1/devices?limit=200&filter[platform]=IOS&filter[status]=ENABLED")
        if s != 200 { fail("list devices failed (\(s))", j) }
        deviceIds = ((j["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
    }
    // Profile name (must be unique per bundle id so multiple profiles for one
    // app — e.g. app + extension — don't clobber each other on regeneration).
    let profileName = env["ADHOC_PROFILE_NAME"] ?? "Ad Hoc"
    // Delete any existing profile(s) with this name so re-running regenerates with
    // the current device list (the profiles endpoint has no filter[name]).
    let (ls, lj) = api("GET", "/v1/profiles?limit=200")
    if ls == 200 {
        for p in (lj["data"] as? [[String: Any]]) ?? [] {
            let name = (p["attributes"] as? [String: Any])?["name"] as? String
            if name == profileName, let pid = p["id"] as? String {
                _ = api("DELETE", "/v1/profiles/\(pid)")
            }
        }
    }
    let body: [String: Any] = ["data": [
        "type": "profiles",
        "attributes": ["name": profileName, "profileType": "IOS_APP_ADHOC"],
        "relationships": [
            "bundleId": ["data": ["type": "bundleIds", "id": bundleId]],
            "certificates": ["data": [["type": "certificates", "id": certId]]],
            "devices": ["data": deviceIds.map { ["type": "devices", "id": $0] }],
        ],
    ]]
    let (s, j) = api("POST", "/v1/profiles", body: body)
    guard s == 201, let d = j["data"] as? [String: Any],
          let a = d["attributes"] as? [String: Any],
          let content = a["profileContent"] as? String,
          let prof = Data(base64Encoded: content) else { fail("create profile failed (\(s))", j) }
    try! prof.write(to: URL(fileURLWithPath: out))
    print("wrote \(out) with \(deviceIds.count) device(s)")

case "bundles":
    // List bundle IDs (id<TAB>identifier<TAB>name). Optional prefix filter arg.
    let q = args.count >= 2 ? "&filter[identifier]=\(args[1])" : ""
    let (s, j) = api("GET", "/v1/bundleIds?limit=200\(q)")
    if s != 200 { fail("list bundles failed (\(s))", j) }
    for b in (j["data"] as? [[String: Any]]) ?? [] {
        let id = b["id"] as? String ?? ""
        let a = b["attributes"] as? [String: Any] ?? [:]
        print("\(id)\t\(a["identifier"] as? String ?? "")\t\(a["name"] as? String ?? "")")
    }

default:
    FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8)); exit(2)
}
