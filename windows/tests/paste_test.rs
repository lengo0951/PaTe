use pasteflow_windows::core::simulator::strip_rich_text;

#[test]
fn test_strip_rich_text_formatting() {
    let input = "Line 1\r\nLine 2\r\n\tIndented text";
    let cleaned = strip_rich_text(input);
    assert_eq!(cleaned, "Line 1\nLine 2\n\tIndented text");
}

#[test]
fn test_strip_control_characters() {
    let input = "Hello\x00\x07World\n";
    let cleaned = strip_rich_text(input);
    assert_eq!(cleaned, "HelloWorld\n");
}
