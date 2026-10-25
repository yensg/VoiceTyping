"""Real-model protocol/reuse check. Requires the pinned model and built worker."""
import json
from pathlib import Path
import selectors
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / '.local/worker-build/bin/dictation-worker'
MODEL = ROOT / 'models/ggml-large-v3-turbo.bin'


def line(process, timeout=60):
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        if not selector.select(timeout):
            raise TimeoutError('Worker did not reply')
    value = process.stdout.readline()
    if not value:
        raise RuntimeError('Worker exited without a reply')
    return json.loads(value)


class WorkerChecks(unittest.TestCase):
    def test_reuses_process_and_rejects_bad_requests(self):
        self.assertTrue(WORKER.is_file(), 'Build the resident worker first')
        with subprocess.Popen([str(WORKER), '--model', str(MODEL)], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1) as process:
            try:
                self.assertEqual(line(process)['type'], 'ready')
                process.stdin.write('{bad json}\n'); process.stdin.flush()
                self.assertEqual(line(process)['type'], 'error')
                outputs = []
                for ident in ['first', 'second']:
                    process.stdin.write(json.dumps({'id': ident, 'audio': str(ROOT / 'vendor/whisper.cpp/samples/jfk.wav'), 'language': 'en', 'prompt': ''})+'\n')
                    process.stdin.flush()
                    result = line(process)
                    self.assertEqual(result['id'], ident)
                    self.assertEqual(result['type'], 'result')
                    self.assertIn('ask not what your country can do for you', result['text'].lower())
                    outputs.append(result['text'])
                self.assertEqual(outputs[0], outputs[1])
                process.stdin.write(json.dumps({'id': 'bad-path', 'audio': '/does/not/exist.wav', 'language': 'en'})+'\n'); process.stdin.flush()
                self.assertEqual(line(process)['type'], 'error')
                self.assertIsNone(process.poll())
            finally:
                process.stdin.close()
                process.wait(timeout=10)


if __name__ == '__main__':
    unittest.main()
