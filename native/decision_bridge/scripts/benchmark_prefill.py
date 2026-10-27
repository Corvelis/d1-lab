"""Compare 3B Metal prefill settings using real decisions and identical inputs."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile


def cases(image=None):
    requests = {
        'review-ja': {
            'state': '料理がおいしく、店員さんも親切でした。また行きたいです。',
            'questions': [{'type': 'choice', 'instructions': 'この口コミの印象を選んでください。',
                           'options': [{'name': '好意的', 'description': '満足や称賛'},
                                       {'name': '否定的', 'description': '不満や批判'},
                                       {'name': '中立', 'description': 'どちらでもない'}]}],
        },
        'long-text': {
            'state': ('The order arrived on time. The package was intact. '
                      'The customer asked about the return policy. ') * 48,
            'questions': [{'type': 'choice', 'instructions': 'Choose the topic of this message.',
                           'options': [{'name': 'Returns'}, {'name': 'Payment'}, {'name': 'Other'}]}],
        },
        'yes-no': {
            'state': '二重に請求されました。余分に支払った分を返してください。',
            'questions': [{'type': 'noul', 'instructions': 'この文章は返金を求めていますか？'}],
        },
        'score': {
            'state': '本番システムでログインできません。すべてのお客様が影響を受けています。',
            'questions': [{'type': 'score', 'instructions': '対応の緊急度を評価してください。',
                           'levels': ['通常の問い合わせ', '一部の利用者に影響', '全利用者が利用不能']}],
        },
        'all-options': {
            'state': 'The item is a red apple.',
            'questions': [{'type': 'choice', 'instructions': 'Select the matching description.',
                           'options': [{'name': chr(65 + i),
                                        'description': 'red apple' if i == 0 else f'item {i}'}
                                       for i in range(26)]}],
        },
        'all-levels': {
            'state': 'The user says the service is very good.',
            'questions': [{'type': 'score', 'instructions': 'Rate satisfaction on these levels.',
                           'levels': [f'satisfaction level {i}' for i in range(10)]}],
        },
        'multiple-questions': {
            'state': 'The product arrived broken. Please exchange it.',
            'questions': [{'type': 'noul', 'instructions': 'Is the product damaged?'},
                          {'type': 'choice', 'instructions': 'Choose the department.',
                           'options': [{'name': 'Returns'}, {'name': 'Payment'}, {'name': 'Other'}]}],
        },
    }
    if image:
        requests['image'] = {
            'state': 'Inspect the attached image.', 'mediaPath': str(image), 'mediaType': 'image',
            'questions': [{'type': 'choice', 'instructions': 'Which color dominates this image?',
                           'options': [{'name': 'Red'}, {'name': 'Green'}, {'name': 'Blue'}]}],
        }
    return requests


def read_result(process):
    line = process.stdout.readline()
    if not line:
        raise RuntimeError('The runtime exited before returning a result.')
    result = json.loads(line)
    if 'error' in result:
        raise RuntimeError(result['error'])
    return result


def measure(args, batch, flash, selective=False):
    options = {'performanceMode': 'standard', 'prefillBatchTokens': batch,
               'flashAttention': flash, 'selectiveOutput': selective}
    command = [str(args.cli), str(args.model), 'metal',
               str(args.projector) if args.projector else '-', json.dumps(options)]
    with tempfile.TemporaryFile(mode='w+') as errors:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=errors, text=True)
        try:
            loaded = read_result(process)
            result = {'requestedBatch': batch, 'requestedFlashAttention': flash,
                      'requestedSelectiveOutput': selective,
                      'executionConfig': loaded['executionConfig'], 'cases': {}}
            for name, request in cases(args.image).items():
                runs = []
                for iteration in range(args.repetitions + 2):
                    process.stdin.write(json.dumps(request, ensure_ascii=False) + '\n')
                    process.stdin.flush()
                    run = read_result(process)
                    if iteration >= 2:
                        runs.append(run)
                representative = runs[-1]
                result['cases'][name] = {
                    'repetitions': args.repetitions,
                    'inputTokens': representative['inputTokens'],
                    'medianForwardMs': statistics.median(r['forwardMs'] for r in runs),
                    'medianTotalMs': statistics.median(r['totalMs'] for r in runs),
                    'medianTokPerSec': statistics.median(r['inputTokPerSec'] for r in runs),
                    'physicalFootprintMB': max(r['processMemory'].get('physicalFootprintMB', 0) for r in runs),
                    'results': representative['results'],
                    'forwardMs': [r['forwardMs'] for r in runs],
                    'totalMs': [r['totalMs'] for r in runs],
                }
            return result
        except Exception:
            errors.seek(0)
            print(errors.read()[-2000:])
            raise
        finally:
            process.stdin.close()
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--projector', type=Path)
    parser.add_argument('--image', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repetitions', type=int, default=5)
    parser.add_argument('--compare-selected-output', action='store_true',
                        help='Compare the original output projection with selected answer rows.')
    args = parser.parse_args()
    if args.repetitions < 3 or (args.image and not args.projector):
        parser.error('Use at least three repetitions and supply a projector for image input.')
    report = {'model': args.model.name, 'warmupRunsPerCase': 2, 'variants': []}
    configurations = [(128, 'off', False), (128, 'auto', False), (256, 'off', False),
                      (256, 'auto', False), (512, 'off', False), (512, 'auto', False),
                      (128, 'off', True), (512, 'auto', True), (128, 'off', False)]
    if args.compare_selected_output:
        configurations = [(128, 'off', False), (128, 'off', True),
                          (512, 'auto', True), (128, 'off', False)]
    for batch, flash, selective in configurations:
        variant = measure(args, batch, flash, selective)
        baseline = report['variants'][0]['cases'] if report['variants'] else variant['cases']
        for name, case in variant['cases'].items():
            expected = baseline[name]['results']
            case['selectionMatchesBaseline'] = all(a['selected'] == b['selected']
                                                   for a, b in zip(case['results'], expected))
            case['maxProbabilityDifference'] = max(
                abs(a['probability'] - b['probability'])
                for current, previous in zip(case['results'], expected)
                for a, b in zip(current['probabilities'], previous['probabilities']))
        report['variants'].append(variant)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(f'Batch {batch}, Flash Attention {flash}, selected output {selective}: ' + ', '.join(
            f"{name} {case['medianForwardMs']:.1f} ms" for name, case in variant['cases'].items()), flush=True)
    if any(not case['selectionMatchesBaseline'] or case['maxProbabilityDifference'] > 0.02
           for variant in report['variants'] for case in variant['cases'].values()):
        raise SystemExit('A result changed beyond the probability tolerance; inspect the report.')


if __name__ == '__main__':
    main()
