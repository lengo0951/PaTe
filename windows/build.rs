fn main() {
    println!("cargo:rerun-if-changed=assets/pasteflow.rc");
    println!("cargo:rerun-if-changed=assets/pasteflow.manifest");
    println!("cargo:rerun-if-changed=assets/pasteflow.ico");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        embed_resource::compile("assets/pasteflow.rc", embed_resource::NONE);
    }
}
