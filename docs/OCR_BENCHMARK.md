# OCR Benchmark

This page documents the OCR benchmark results previously shown in the repository README.

## Results

Benchmark date: April 19, 2026. The results below come from a clean synthetic wrapped UI/article-text corpus with 12 samples per language across 10 supported languages. Character accuracy is the primary signal; exact match is intentionally strict. The no-output rate was 0% for every language in this corpus.

| Language            | Character Accuracy | Exact Match |
| ------------------- | -----------------: | ----------: |
| English             |             100.0% |      100.0% |
| Vietnamese          |             100.0% |      100.0% |
| Simplified Chinese  |              99.3% |       75.0% |
| Traditional Chinese |              99.0% |       66.7% |
| Spanish             |              99.9% |       91.7% |
| Japanese            |              99.4% |       66.7% |
| Korean              |              99.7% |       83.3% |
| Russian             |             100.0% |      100.0% |
| French              |              99.3% |       33.3% |
| German              |              99.8% |       75.0% |

These results are specific to the synthetic corpus. Real-world screenshots can score lower, especially with emoji, low-contrast footers, unusual punctuation, gradients, blur, or decorative fonts.

## Reproduce

Run the benchmark from the repository root on macOS with Xcode Command Line Tools installed:

```bash
./scripts/run-ocr-readme-benchmark.sh
```

The script compiles and runs the benchmark using `swiftc`. It prints per-language character accuracy, exact-match rate, no-output rate, average confidence, and average latency. The benchmark source is [`scripts/swift-tools/ocr/ocr-readme-benchmark.swift`](../scripts/swift-tools/ocr/ocr-readme-benchmark.swift).
