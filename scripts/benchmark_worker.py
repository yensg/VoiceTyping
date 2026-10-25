"""Local, identical-audio latency comparison; writes no personal audio."""
import json
import statistics
import subprocess
import time
from check_worker import ROOT, WORKER, MODEL, line

results = {'audio': 'upstream jfk.wav (11 seconds)', 'model': MODEL.name, 'cli_seconds': [], 'resident_seconds': [], 'same_words': True}
with subprocess.Popen([str(WORKER), '--model', str(MODEL)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1) as process:
    try:
        results['model_load_ms'] = line(process)['load_ms']
        for index in range(5):
            before = time.monotonic()
            cli = subprocess.run([str(ROOT/'.local/engine-build/bin/whisper-cli'), '-m', str(MODEL), '-f', str(ROOT/'vendor/whisper.cpp/samples/jfk.wav'), '-l', 'en', '-nt', '-np', '--no-speech-thold', '0.6'], capture_output=True, text=True, check=True)
            results['cli_seconds'].append(time.monotonic()-before)
            before = time.monotonic()
            process.stdin.write(json.dumps({'id': str(index), 'audio': str(ROOT/'vendor/whisper.cpp/samples/jfk.wav'), 'language': 'en'})+'\n'); process.stdin.flush()
            reply = line(process)
            results['resident_seconds'].append(time.monotonic()-before)
            results['same_words'] &= cli.stdout.split() == reply['text'].split()
    finally:
        process.stdin.close(); process.wait(timeout=10)
results['cli_median'] = statistics.median(results['cli_seconds'])
results['resident_median'] = statistics.median(results['resident_seconds'])
results['reduction_percent'] = 100*(1-results['resident_median']/results['cli_median'])
(ROOT/'.local/latency-resident.json').write_text(json.dumps(results, indent=2)+'\n')
print(json.dumps(results, indent=2))
