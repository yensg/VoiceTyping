#!/usr/bin/env python3
"""Score a consented local JSONL corpus; no uploads or audio collection."""
import argparse
import json
import re
import unicodedata


def words(text):
    text = unicodedata.normalize('NFKC', text).casefold()
    return re.findall(r"\w+(?:'\w+)*", text)


def edits(reference, hypothesis):
    row = list(range(len(hypothesis) + 1))
    for i, left in enumerate(reference, 1):
        next_row = [i]
        for j, right in enumerate(hypothesis, 1):
            next_row.append(min(row[j] + 1, next_row[j-1] + 1, row[j-1] + (left != right)))
        row = next_row
    return row[-1]


def score(rows):
    total = errors = 0
    misses = []
    for index, item in enumerate(rows, 1):
        reference, hypothesis = words(item['reference']), words(item['hypothesis'])
        total += len(reference)
        errors += edits(reference, hypothesis)
        normalized = ' ' + ' '.join(hypothesis) + ' '
        for term in item.get('key_terms', []):
            if ' ' + ' '.join(words(term)) + ' ' not in normalized:
                misses.append({'row': index, 'term': term})
    return {'reference_words': total, 'word_edits': errors,
            'wer': errors / total if total else None, 'key_term_misses': misses}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('corpus', help='JSONL with reference, hypothesis and optional key_terms')
    args = parser.parse_args()
    with open(args.corpus) as source:
        rows = [json.loads(line) for line in source if line.strip()]
    print(json.dumps(score(rows), indent=2, ensure_ascii=False))
