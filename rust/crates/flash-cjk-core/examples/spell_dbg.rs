fn main() {
    let sp = flash_cjk_core::predict::spellings("日本", &flash_cjk_core::Langs::default());
    println!("count={} first8={:?}", sp.len(), &sp[..sp.len().min(8)]);
    let ni: Vec<&String> = sp.iter().filter(|s| s.starts_with("ni")).collect();
    println!("ni-prefixed: {:?}", ni);
    println!(
        "letters/tags: {:?}",
        flash_cjk_core::predict::predict("ni", "日本", &flash_cjk_core::Langs::default())
    );
}
