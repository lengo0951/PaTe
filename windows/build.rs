fn main() {
    println!("cargo:rerun-if-changed=assets/pate.rc");
    println!("cargo:rerun-if-changed=assets/pate.manifest");
    println!("cargo:rerun-if-changed=assets/pate.ico");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        embed_resource::compile("assets/pate.rc", embed_resource::NONE);
    }
}
