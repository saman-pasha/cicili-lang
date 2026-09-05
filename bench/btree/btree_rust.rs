// the same workload on Rust's BTreeSet (B = 6: up to 11 keys per node)
use std::collections::BTreeSet;
use std::time::Instant;
fn key_of(i: u32) -> i32 { i.wrapping_mul(2654435761) as i32 }
fn main() {
    let n: u32 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1_000_000);
    let t = Instant::now();
    let mut s = BTreeSet::new();
    for i in 0..n { s.insert(key_of(i)); }
    let ins = t.elapsed().as_millis();
    let t = Instant::now();
    let mut found = 0u32;
    for i in n / 2..n / 2 + n { if s.contains(&key_of(i)) { found += 1; } }
    let srch = t.elapsed().as_millis();
    let t = Instant::now();
    drop(s);
    let fr = t.elapsed().as_millis();
    println!("rust -O3     insert {} ms  search {} ms  free {} ms  found {}", ins, srch, fr, found);
}
