"""Check typed decisions for current and earlier GGUF releases."""
import argparse
import json
import math
from pathlib import Path
import subprocess


REQUEST = {
    'state': '料理がおいしく、店員の対応も親切でした。また行きたいです。',
    'calibrated': True,
    'questions': [
        {'type': 'choice', 'instructions': 'この口コミの印象を選んでください。',
         'options': [{'name': '好意的', 'description': '満足している'},
                     {'name': '否定的', 'description': '不満がある'},
                     {'name': '中立', 'description': '評価していない'}]},
        {'type': 'noul', 'instructions': 'この口コミは再訪したいと述べていますか？'},
        {'type': 'score', 'instructions': 'この口コミの満足度を評価してください。',
         'levels': ['不満', '普通', '満足']},
    ],
}
MODELS = [('d1-3B', 'd1-3B-Q4_K_M.gguf'),
          ('d1-omni-600M', 'd1-omni-600M-Q8_0.gguf')]


def evaluate(cli, directory, backend):
    answers = {}
    for name, filename in MODELS:
        result = subprocess.run(
            [str(cli.resolve()), str((directory / filename).resolve()), backend],
            input=json.dumps(REQUEST, ensure_ascii=False) + '\n',
            text=True, encoding='utf-8', errors='replace', capture_output=True,
            timeout=180, check=True)
        lines = result.stdout.strip().splitlines()
        if len(lines) != 2:
            raise ValueError(f'{name}: expected load and decision responses')
        loaded, run = (json.loads(line) for line in lines)
        for response in [loaded, run]:
            if 'error' in response:
                raise ValueError(f'{name}: {response["error"]}')
            if response.get('model') != name:
                raise ValueError(f'{name}: incorrect model recognition')
        if backend == 'metal' and run['placement']['gpuTensors'] <= 0:
            raise ValueError(f'{name}: model weights were not placed on Metal')
        if [item['type'] for item in run['results']] != ['choice', 'noul', 'score']:
            raise ValueError(f'{name}: typed questions were not preserved')
        for item in run['results']:
            probabilities = [p['probability'] for p in item['probabilities']]
            if (not all(math.isfinite(p) and 0 <= p <= 1 for p in probabilities)
                    or abs(sum(probabilities) - 1) > 1e-6):
                raise ValueError(f'{name}: invalid probability distribution')
        answers[name] = run['results']
    return answers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--current-models', type=Path, required=True)
    parser.add_argument('--previous-models', type=Path)
    parser.add_argument('--expect-parity', action='store_true',
                        help='Require matching results when both releases have identical weights.')
    parser.add_argument('--backend', choices=['cpu', 'metal'], default='metal')
    args = parser.parse_args()
    current = evaluate(args.cli, args.current_models, args.backend)
    if args.previous_models:
        previous = evaluate(args.cli, args.previous_models, args.backend)
        if args.expect_parity:
            for name in current:
                for before, after in zip(previous[name], current[name]):
                    if before['selected'] != after['selected'] or before['temperature'] != after['temperature']:
                        raise ValueError(f'{name}: release changed the selected answer or calibration')
                    for left, right in zip(before['probabilities'], after['probabilities']):
                        if left['label'] != right['label'] or abs(left['probability'] - right['probability']) > 1e-5:
                            raise ValueError(f'{name}: release changed the probability distribution')
    print(('Current and previous models' if args.previous_models else 'Current models') +
          ' passed Choice, Noul and Score checks.')


if __name__ == '__main__':
    main()
