use crate::{ffi_result, WIFI_LENS_STATUS_PANIC};

#[test]
fn ffi_boundary_catches_panics() {
    let result = ffi_result(|| panic!("test panic"));

    assert_eq!(result.status, WIFI_LENS_STATUS_PANIC);
    assert_eq!((result.left, result.right), (0, 0));
}
