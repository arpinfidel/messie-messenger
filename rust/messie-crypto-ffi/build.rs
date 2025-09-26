fn main() {
    uniffi_build::generate_scaffolding("src/native_crypto.udl").expect("failed to generate uniffi scaffolding");
}
