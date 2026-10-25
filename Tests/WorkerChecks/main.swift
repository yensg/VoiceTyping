import Foundation
import DictationCore

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let script = directory.appendingPathComponent("worker.py")
try """
import json, os, sys, time
print(json.dumps({'type':'ready'}), flush=True)
for line in sys.stdin:
    obj=json.loads(line)
    if obj['id']=='wait': time.sleep(30)
    if obj['id']=='crash': sys.exit(1)
    if obj['id']=='bad': print('bad', flush=True); continue
    print(json.dumps({'type':'result','id':obj['id'],'text':str(os.getpid())}), flush=True)
""".write(to: script, atomically: true, encoding: .utf8)
let worker = ResidentWorker(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path])
defer { worker.close() }
try worker.warm()
let first = try worker.request(["id":"one"])
let second = try worker.request(["id":"two"])
precondition(second == first, "Worker must be reused")
for id in ["bad", "crash"] {
    do { _ = try worker.request(["id":id]); fatalError("Invalid reply accepted") } catch {}
    _ = try worker.request(["id":"recovery"])
}
let started = DispatchSemaphore(value: 0), completed = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    started.signal()
    do { _ = try worker.request(["id":"wait"]); fatalError("Cancelled work returned") } catch {}
    completed.signal()
}
started.wait(); Thread.sleep(forTimeInterval: 0.2)
worker.cancel()
precondition(completed.wait(timeout: .now()+3) == .success, "Cancel must unblock reader")
_ = try worker.request(["id":"after-cancel"])
worker.close()
print("Resident worker reuse, malformed reply, crash recovery and cancellation passed")
