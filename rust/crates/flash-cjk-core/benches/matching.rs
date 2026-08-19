//! Benchmarks mirroring the real workload: a ~60-line mixed CJK window
//! re-matched on every keystroke as the pattern grows.

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};
use flash_cjk_core::{compile, find_matches, Langs};

fn bench_lines() -> Vec<String> {
    (1..=60)
        .map(|i| {
            format!(
                "日本語のテスト行{i}です 中文混合内容 你好世界第{i}行 안녕하세요 한국어 텍스트 {i} english foo{i} end"
            )
        })
        .collect()
}

fn bench_matching(c: &mut Criterion) {
    let lines_owned = bench_lines();
    let lines: Vec<&str> = lines_owned.iter().map(String::as_str).collect();
    let langs = Langs::default();

    let mut group = c.benchmark_group("keystroke");
    for pat in ["n", "ni", "nih", "niho", "kanji", "dks", "dkss", "kim"] {
        let alts = compile(pat, langs);
        group.bench_with_input(BenchmarkId::new("full", pat), pat, |b, _| {
            b.iter(|| {
                let alts = compile(pat, langs);
                find_matches(std::hint::black_box(&lines), &alts)
            })
        });
        group.bench_with_input(BenchmarkId::new("match_only", pat), pat, |b, _| {
            b.iter(|| find_matches(std::hint::black_box(&lines), &alts))
        });
    }
    group.finish();

    // compile cost in isolation (per new keystroke the Lua side also
    // recompiles; here we measure the Rust equivalent)
    let mut group = c.benchmark_group("compile");
    for pat in ["ni", "niho", "kanjix"] {
        group.bench_with_input(BenchmarkId::new("pattern", pat), pat, |b, _| {
            b.iter(|| compile(std::hint::black_box(pat), langs))
        });
    }
    group.finish();
}

fn bench_scaling(c: &mut Criterion) {
    // window-size scaling at a realistic mid-length pattern
    for size in [60usize, 200, 600] {
        let lines_owned: Vec<String> = (1..=size)
            .map(|i| format!("日本語のテスト行{i}です 中文混合内容 你好第{i}行 안녕하세요 한국어 {i} english foo{i} end"))
            .collect();
        let lines: Vec<&str> = lines_owned.iter().map(String::as_str).collect();
        let alts = compile("nih", Langs::default());
        c.benchmark_group("scaling").bench_with_input(
            BenchmarkId::new("vim_semantics", size),
            &lines,
            |b, ls| b.iter(|| find_matches(std::hint::black_box(ls), &alts)),
        );
    }
}

criterion_group!(benches, bench_matching, bench_scaling);
criterion_main!(benches);
