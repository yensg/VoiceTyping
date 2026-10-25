import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('builder', Path(__file__).with_name('build.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

class BuildTests(unittest.TestCase):
    def test_missing_folders_created_without_overwriting_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            builder.ensure_directories(root, ['models', '.planning'])
            self.assertTrue((root / '.planning').is_dir())
            note = root / '.planning' / 'state.md'
            note.write_text('keep my work')
            builder.ensure_directories(root, ['models', '.planning'])
            self.assertEqual(note.read_text(), 'keep my work')
            self.assertTrue((root / 'models').is_dir())

    def test_symlink_cannot_redirect_output_outside_project(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as elsewhere:
            root = Path(directory)
            (root / 'models').symlink_to(elsewhere)
            with self.assertRaises(ValueError):
                builder.ensure_directories(root, ['models'])

    def test_bundle_file_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as elsewhere:
            root = Path(directory)
            victim = Path(elsewhere) / 'keep.txt'
            victim.write_text('keep')
            output = root / 'engine.json'
            output.symlink_to(victim)
            with self.assertRaises(ValueError):
                builder.checked_output(root, output)
            self.assertEqual(victim.read_text(), 'keep')
            self.assertEqual(builder.checked_output(root, root / 'new.json'), root / 'new.json')

    def test_packaging_rejects_corrupted_model_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            builder.ensure_directories(root, ['models', '.local/worker-build/bin'])
            (root / 'models/model.bin').write_bytes(b'bad')
            (root / '.local/worker-build/bin/dictation-worker').write_bytes(b'engine')
            lock = {'model': {'filename': 'model.bin', 'size': 3, 'sha256': hashlib.sha256(b'yes').hexdigest()}}
            with patch.object(builder, 'ROOT', root), patch.object(builder, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'integrity'):
                    builder.app(lock)
                run.assert_not_called()

    def test_checksum_failure_keeps_existing_model(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pending = root / 'pending'
            target = root / 'model'
            target.write_bytes(b'known good')
            pending.write_bytes(b'corrupt')
            with self.assertRaises(ValueError):
                builder.promote_verified(pending, target, '0' * 64)
            self.assertEqual(target.read_bytes(), b'known good')
            pending.write_bytes(b'new verified')
            builder.promote_verified(pending, target, hashlib.sha256(b'new verified').hexdigest())
            self.assertEqual(target.read_bytes(), b'new verified')

if __name__ == '__main__':
    unittest.main()
